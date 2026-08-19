#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Reindex ONLY the sessions and agenda items that exist in the triplestore but
# are missing from the mu-search index. Per location it diffs the triplestore
# ids against the indexed ids (within a date window to keep buckets small) and
# pushes just the missing documents to mu-search's /update endpoint. This keeps
# the update queue tiny -- unlike a full reindex or re-pushing everything.
#
# Run INSIDE the search container (only Ruby stdlib is used):
#   docker compose exec -T search ruby - < scripts/reindex-missing.rb                 # all time (no date)
#   docker compose exec -T search ruby - 2026-01-01 < scripts/reindex-missing.rb       # from a date
#   docker compose exec -T search ruby - 2026-01-01 Asse < scripts/reindex-missing.rb  # from a date, one bestuurseenheid
#
# With no date it checks all time. Note Elasticsearch only returns the first
# 10000 hits per query, so for a location whose index has more than that in a
# type (mainly agenda items for big cities over all time), the diff can't be
# trusted; that (type, location) is skipped with a warning -- re-run it with a
# from-date for that bestuurseenheid.
#
# Env (defaults assume it runs inside the search container):
#   SPARQL_ENDPOINT  default http://triplestore:8890/sparql
#   SEARCH_BASE      default http://search
#   ALLOWED_GROUPS   default [{"variables":[],"name":"public"}]
#   BATCH            default 100   (docs per /update POST)
#   THROTTLE_MS      default 200   (pause between POSTs)

require 'net/http'
require 'json'
require 'uri'
require 'set'
require 'time'

SPARQL_ENDPOINT = ENV.fetch('SPARQL_ENDPOINT', 'http://triplestore:8890/sparql')
SEARCH_BASE     = ENV.fetch('SEARCH_BASE', 'http://search').chomp('/')
ALLOWED_GROUPS  = ENV.fetch('ALLOWED_GROUPS', '[{"variables":[],"name":"public"}]')
BATCH           = Integer(ENV.fetch('BATCH', '100'))
THROTTLE        = Float(ENV.fetch('THROTTLE_MS', '200')) / 1000.0
SPARQL_PAGE     = 10_000     # Virtuoso row cap
INDEX_PAGE      = 1_000
INDEX_MAX       = 10_000     # Elasticsearch from+size cap

TYPE_PRED       = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type'
ZITTING_TYPE    = 'http://data.vlaanderen.be/ns/besluit#Zitting'
AGENDAPUNT_TYPE = 'http://data.vlaanderen.be/ns/besluit#Agendapunt'

PREFIXES = <<~SPARQL
  PREFIX besluit: <http://data.vlaanderen.be/ns/besluit#>
  PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
  PREFIX mandaat: <http://data.vlaanderen.be/ns/mandaat#>
  PREFIX mu: <http://mu.semte.ch/vocabularies/core/>
  PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
SPARQL

from_date       = (ARGV[0] || '').strip   # empty = all time
bestuurseenheid = (ARGV[1] || '').strip

def log(msg)
  puts("[#{Time.now.utc.iso8601}] #{msg}")
end

def sparql_select(query)
  uri = URI(SPARQL_ENDPOINT)
  req = Net::HTTP::Post.new(uri)
  req.set_form_data('query' => query, 'format' => 'application/sparql-results+json')
  req['Accept'] = 'application/sparql-results+json'
  res = Net::HTTP.start(uri.hostname, uri.port, read_timeout: 600) { |http| http.request(req) }
  raise "SPARQL #{res.code}: #{res.body.to_s[0, 300]}" unless res.code.to_i == 200

  JSON.parse(res.body)['results']['bindings']
end

# {uuid => uri} for a SELECT ?uri ?uuid, paged under Virtuoso's row cap.
def fetch_pairs(where, uri_var)
  pairs = {}
  offset = 0
  loop do
    q = "#{PREFIXES}\nSELECT DISTINCT ?#{uri_var} ?uuid WHERE {\n#{where}\n} ORDER BY ?#{uri_var} LIMIT #{SPARQL_PAGE} OFFSET #{offset}"
    rows = sparql_select(q)
    rows.each { |b| pairs[b['uuid']['value']] = b[uri_var]['value'] }
    break if rows.size < SPARQL_PAGE

    offset += SPARQL_PAGE
  end
  pairs
end

# [Set of indexed document ids, truncated?]. Truncated means the index holds
# more than Elasticsearch will page through (10k), so the diff can't be trusted.
def index_ids(type, filters)
  ids = Set.new
  number = 0
  total = nil
  loop do
    params = ["page[size]=#{INDEX_PAGE}", "page[number]=#{number}"] + filters
    uri = URI("#{SEARCH_BASE}/#{type}/search?#{params.join('&')}")
    req = Net::HTTP::Get.new(uri)
    req['mu-auth-allowed-groups'] = ALLOWED_GROUPS
    res = Net::HTTP.start(uri.hostname, uri.port, read_timeout: 120) { |http| http.request(req) }
    break unless res.code.to_i == 200

    body = JSON.parse(res.body)
    total ||= (body['count'] || 0).to_i
    data = body['data'] || []
    data.each { |d| ids << d['id'] }
    number += 1
    break if data.size < INDEX_PAGE

    if number * INDEX_PAGE >= INDEX_MAX
      return [ids, true] if total > INDEX_MAX

      break
    end
  end
  [ids, false]
end

def post_delta(inserts)
  body = [{ 'inserts' => inserts, 'deletes' => [] }].to_json
  uri = URI("#{SEARCH_BASE}/update")
  req = Net::HTTP::Post.new(uri)
  req['Content-Type'] = 'application/json'
  req['mu-auth-allowed-groups'] = ALLOWED_GROUPS
  req.body = body
  res = Net::HTTP.start(uri.hostname, uri.port, read_timeout: 600) { |http| http.request(req) }
  return if (200..299).include?(res.code.to_i)

  raise "search /update #{res.code}: #{res.body.to_s[0, 200]}"
end

def push(docs)
  docs.each_slice(BATCH) do |slice|
    inserts = slice.map do |(subject, type)|
      {
        'subject'   => { 'type' => 'uri', 'value' => subject },
        'predicate' => { 'type' => 'uri', 'value' => TYPE_PRED },
        'object'    => { 'type' => 'uri', 'value' => type }
      }
    end
    post_delta(inserts)
    sleep THROTTLE
  end
end

date = from_date.empty? ? '' : %(?z besluit:geplandeStart ?start . FILTER(?start >= "#{from_date}T00:00:00+00:00"^^xsd:dateTime))
ee_clause = bestuurseenheid.empty? ? '' : %(; skos:prefLabel "#{bestuurseenheid.gsub('\\', '\\\\\\\\').gsub('"', '\\"')}")
loc_scope = <<~SPARQL
  ?ee a besluit:Bestuurseenheid ; besluit:werkingsgebied ?wg #{ee_clause} .
  ?bo besluit:bestuurt ?ee .
  ?org (mandaat:isTijdspecialisatieVan?) ?bo .
  ?z besluit:isGehoudenDoor ?org .
SPARQL

log("Reindex-missing: #{from_date.empty? ? 'all time' : "from #{from_date}"}#{bestuurseenheid.empty? ? '' : " (#{bestuurseenheid})"}")

locations = sparql_select(<<~SPARQL).map { |b| [b['loc']['value'], b['label']['value']] }
  #{PREFIXES}
  SELECT DISTINCT ?label ?loc WHERE {
    ?ee a besluit:Bestuurseenheid ; skos:prefLabel ?label ; besluit:werkingsgebied ?wg #{ee_clause} .
    ?wg mu:uuid ?loc .
    ?bo besluit:bestuurt ?ee .
    ?org (mandaat:isTijdspecialisatieVan?) ?bo .
    ?z besluit:isGehoudenDoor ?org .
    #{date}
  } ORDER BY ?label
SPARQL
log("#{locations.size} locations to check.")

# Index date filters (only when a from-date is given; nil = all time).
ses_date = from_date.empty? ? nil : "filter[:query:planned_start]=#{URI.encode_www_form_component("planned_start:[#{from_date} TO *]")}"
agi_date = from_date.empty? ? nil : "filter[:query:session_planned_start]=#{URI.encode_www_form_component("session_planned_start:[#{from_date} TO *]")}"

# Phase 1: scan every location and collect the missing documents (no indexing yet).
missing = []
n_sessions = 0
n_agenda = 0
locations.each do |loc, label|
  loc_filter = "filter[:terms:search_location_id]=#{URI.encode_www_form_component(loc)}"

  ses_idx, ses_trunc = index_ids('sessions', [loc_filter, ses_date].compact)
  if ses_trunc
    log("  #{label}: >#{INDEX_MAX} indexed sessions; skipping (re-run with a from-date for this bestuurseenheid)")
    missing_sessions = {}
  else
    ses_ts = fetch_pairs(%(?wg mu:uuid "#{loc}" .\n#{loc_scope}\n?z mu:uuid ?uuid .\n#{date}), 'z')
    missing_sessions = ses_ts.reject { |uuid, _| ses_idx.include?(uuid) }
  end

  agi_idx, agi_trunc = index_ids('agenda-items', [loc_filter, agi_date].compact)
  if agi_trunc
    log("  #{label}: >#{INDEX_MAX} indexed agenda items; skipping (re-run with a from-date for this bestuurseenheid)")
    missing_agenda = {}
  else
    agi_ts = fetch_pairs(%(?wg mu:uuid "#{loc}" .\n#{loc_scope}\n#{date}\n?z besluit:behandelt ?ai .\n?ai mu:uuid ?uuid .), 'ai')
    missing_agenda = agi_ts.reject { |uuid, _| agi_idx.include?(uuid) }
  end

  next if missing_sessions.empty? && missing_agenda.empty?

  n_sessions += missing_sessions.size
  n_agenda += missing_agenda.size
  missing.concat(missing_sessions.values.map { |u| [u, ZITTING_TYPE] })
  missing.concat(missing_agenda.values.map { |u| [u, AGENDAPUNT_TYPE] })
  log("  #{label}: missing #{missing_sessions.size} sessions + #{missing_agenda.size} agenda-items")
end

total = n_sessions + n_agenda
log("Scan complete: #{n_sessions} missing sessions + #{n_agenda} missing agenda items (#{total} documents).")

if total.zero?
  log('Index is already in sync; nothing to do.')
  exit 0
end

log("Indexing #{total} documents...")
push(missing)
log("Done. Pushed #{total} missing documents to mu-search.")
