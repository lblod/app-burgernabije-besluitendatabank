#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Nightly reconciliation between the triplestore (source of truth) and the
# mu-search index. The index is fed only by best-effort live delta
# notifications, which drop events under load, so it slowly drifts out of sync
# (worst for recent data). This job detects, per bestuurseenheid, where the
# triplestore has more sessions than the index within a recent window, and
# reindexes just those by re-asserting their rdf:type to mu-search's /update
# endpoint. It mutates no data.
#
# Runs as a loop (see the `search-reconciler` service in docker-compose.yml).
# Can also be run once by hand:
#   docker compose exec -T search ruby - < scripts/reconcile-search.rb
#
# Env:
#   SPARQL_ENDPOINT          default http://triplestore:8890/sparql
#   SEARCH_BASE              default http://search   (mu-search base URL)
#   ALLOWED_GROUPS           default [{"variables":[],"name":"public"}]
#   RECONCILE_FROM           ISO date (e.g. 2026-01-01); overrides RECONCILE_DAYS
#   RECONCILE_DAYS           lookback window in days (default 120)
#   RECONCILE_INTERVAL_HOURS loop interval; 0/unset = run once and exit (default 24)
#   BATCH                    documents per /update POST (default 200)

require 'net/http'
require 'json'
require 'uri'
require 'date'
require 'time'

SPARQL_ENDPOINT = ENV.fetch('SPARQL_ENDPOINT', 'http://triplestore:8890/sparql')
SEARCH_BASE     = ENV.fetch('SEARCH_BASE', 'http://search').chomp('/')
ALLOWED_GROUPS  = ENV.fetch('ALLOWED_GROUPS', '[{"variables":[],"name":"public"}]')
BATCH           = Integer(ENV.fetch('BATCH', '200'))
# Pause between /update POSTs so a backlog of stale municipalities does not
# saturate mu-search (which then stops accepting connections / drops live deltas).
THROTTLE        = Float(ENV.fetch('THROTTLE_MS', '300')) / 1000.0
PAGE            = 10_000

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

def log(msg)
  puts "[#{Time.now.utc.iso8601}] #{msg}"
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

def fetch_uris(where, var)
  out = []
  offset = 0
  loop do
    q = "#{PREFIXES}\nSELECT DISTINCT ?#{var} WHERE {\n#{where}\n} ORDER BY ?#{var} LIMIT #{PAGE} OFFSET #{offset}"
    rows = sparql_select(q).map { |b| b[var]['value'] }
    out.concat(rows)
    break if rows.size < PAGE

    offset += PAGE
  end
  out
end

def date_filter(from_date)
  %(?z besluit:geplandeStart ?start . FILTER(?start >= "#{from_date}T00:00:00+00:00"^^xsd:dateTime))
end

# Index session count for one location, same date window. page[size]=1 because
# mu-search returns HTTP 500 for size 0.
def index_count(loc, from_date)
  params = [
    'page[size]=1',
    "filter[:terms:search_location_id]=#{URI.encode_www_form_component(loc)}",
    "filter[:query:planned_start]=#{URI.encode_www_form_component("planned_start:[#{from_date} TO *]")}"
  ]
  uri = URI("#{SEARCH_BASE}/sessions/search?#{params.join('&')}")
  req = Net::HTTP::Get.new(uri)
  req['mu-auth-allowed-groups'] = ALLOWED_GROUPS
  res = Net::HTTP.start(uri.hostname, uri.port, read_timeout: 120) { |http| http.request(req) }
  return 0 unless res.code.to_i == 200

  (JSON.parse(res.body)['count'] || 0).to_i
rescue StandardError => e
  log("  index count failed for #{loc}: #{e.message}")
  0
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

# Reindex all sessions + agenda items for one location within the window.
def reindex_location(loc, from_date)
  scope = <<~SPARQL
    ?wg mu:uuid "#{loc}" .
    ?ee a besluit:Bestuurseenheid ; besluit:werkingsgebied ?wg .
    ?bo besluit:bestuurt ?ee .
    ?org (mandaat:isTijdspecialisatieVan?) ?bo .
    ?z besluit:isGehoudenDoor ?org .
  SPARQL
  date = date_filter(from_date)

  session_uris = fetch_uris("#{scope}\n#{date}", 'z')
  agenda_uris  = fetch_uris("#{scope}\n?z besluit:behandelt ?ai .\n#{date}", 'ai')
  docs = session_uris.map { |u| [u, ZITTING_TYPE] } + agenda_uris.map { |u| [u, AGENDAPUNT_TYPE] }

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
  docs.size
end

def reconcile
  from_date =
    if ENV['RECONCILE_FROM'] && !ENV['RECONCILE_FROM'].strip.empty?
      ENV['RECONCILE_FROM'].strip
    else
      (Date.today - Integer(ENV.fetch('RECONCILE_DAYS', '120'))).iso8601
    end

  log("Reconcile start (window from #{from_date}); triplestore=#{SPARQL_ENDPOINT} search=#{SEARCH_BASE}")

  query = <<~SPARQL
    #{PREFIXES}
    SELECT ?label ?loc (COUNT(DISTINCT ?z) AS ?c) WHERE {
      ?ee a besluit:Bestuurseenheid ; skos:prefLabel ?label ; besluit:werkingsgebied ?wg .
      ?wg mu:uuid ?loc .
      ?bo besluit:bestuurt ?ee .
      ?org (mandaat:isTijdspecialisatieVan?) ?bo .
      #{date_filter(from_date)}
    } GROUP BY ?label ?loc ORDER BY ?label
  SPARQL

  rows = sparql_select(query)
  log("Checking #{rows.size} bestuurseenheden against the index...")

  stale = 0
  reindexed_docs = 0
  rows.each do |b|
    loc   = b['loc']['value']
    label = b['label']['value']
    ts    = b['c']['value'].to_i
    idx   = index_count(loc, from_date)
    next unless ts > idx

    stale += 1
    n = reindex_location(loc, from_date)
    reindexed_docs += n
    log("  #{label}: store=#{ts} index=#{idx} -> pushed #{n} documents")
  end

  log("Reconcile done: #{stale} stale bestuurseenheden, #{reindexed_docs} documents pushed to mu-search.")
rescue StandardError => e
  log("Reconcile FAILED: #{e.class}: #{e.message}")
end

interval_hours = Integer(ENV.fetch('RECONCILE_INTERVAL_HOURS', '24'))
loop do
  reconcile
  break if interval_hours <= 0

  log("Sleeping #{interval_hours}h until next reconcile.")
  sleep interval_hours * 3600
end
