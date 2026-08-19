#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Scoped (re)index of sessions (besluit:Zitting) and their agenda items
# (besluit:Agendapunt) in mu-search, for a single bestuurseenheid (and/or from a
# date). Use this to backfill documents that are present in the triplestore but
# missing from the search index, without rebuilding the whole index.
#
# It works by sending a v0.0.1 delta to mu-search's /update endpoint that
# re-asserts the rdf:type of each in-scope document, which makes mu-search
# re-fetch and (re)index those specific documents. It mutates no data.
#
# IMPORTANT: the index is built for the `public` group, so the delta is sent with
# the `mu-auth-allowed-groups` header set to public. Without it mu-search has no
# group to update and silently does nothing.
#
# Run it INSIDE the search container (only Ruby stdlib is used):
#
#   docker compose exec -T search ruby - Asse < scripts/reindex-search.rb
#   docker compose exec -T search ruby - Asse 2026-01-01 < scripts/reindex-search.rb
#   docker compose exec -T search ruby - "" 2026-01-01 < scripts/reindex-search.rb   # all, from a date
#
# Watch progress with:  docker compose logs -f search
#
# Env overrides (defaults assume it runs inside the search container):
#   SPARQL_ENDPOINT  default http://triplestore:8890/sparql
#   SEARCH_ENDPOINT  default http://localhost/update   (mu-search itself, port 80)
#   ALLOWED_GROUPS   default [{"variables":[],"name":"public"}]
#   BATCH            default 100   (documents per /update POST)
#
# If you run it from another container instead of `search`, set
#   SEARCH_ENDPOINT=http://search/update

require 'net/http'
require 'json'
require 'uri'

SPARQL_ENDPOINT = ENV.fetch('SPARQL_ENDPOINT', 'http://triplestore:8890/sparql')
SEARCH_ENDPOINT = ENV.fetch('SEARCH_ENDPOINT', 'http://localhost/update')
ALLOWED_GROUPS  = ENV.fetch('ALLOWED_GROUPS', '[{"variables":[],"name":"public"}]')
BATCH           = Integer(ENV.fetch('BATCH', '100'))
# Pause between /update POSTs so a big backfill does not saturate mu-search
# (which then stops accepting connections / drops live deltas).
THROTTLE        = Float(ENV.fetch('THROTTLE_MS', '200')) / 1000.0
PAGE            = 10_000 # stay under Virtuoso's default ResultSetMaxRows

TYPE_PRED       = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type'
ZITTING_TYPE    = 'http://data.vlaanderen.be/ns/besluit#Zitting'
AGENDAPUNT_TYPE = 'http://data.vlaanderen.be/ns/besluit#Agendapunt'

PREFIXES = <<~SPARQL
  PREFIX besluit: <http://data.vlaanderen.be/ns/besluit#>
  PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
  PREFIX mandaat: <http://data.vlaanderen.be/ns/mandaat#>
  PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
SPARQL

bestuurseenheid = (ARGV[0] || '').strip
from_date       = (ARGV[1] || '').strip

def scope_clause(bestuurseenheid)
  return '?z a besluit:Zitting .' if bestuurseenheid.empty?

  label = bestuurseenheid.gsub('\\', '\\\\\\\\').gsub('"', '\\"')
  <<~SPARQL
    ?ee a besluit:Bestuurseenheid ; skos:prefLabel "#{label}" .
    ?bo besluit:bestuurt ?ee .
    ?org (mandaat:isTijdspecialisatieVan?) ?bo .
    ?z besluit:isGehoudenDoor ?org .
  SPARQL
end

def date_clause(from_date)
  return '' if from_date.empty?

  %(?z besluit:geplandeStart ?start . FILTER(?start >= "#{from_date}T00:00:00+00:00"^^xsd:dateTime))
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

# Paged fetch so big scopes aren't silently capped by Virtuoso.
def fetch_uris(where, var)
  out = []
  offset = 0
  loop do
    query = "#{PREFIXES}\nSELECT DISTINCT ?#{var} WHERE {\n#{where}\n} ORDER BY ?#{var} LIMIT #{PAGE} OFFSET #{offset}"
    rows = sparql_select(query).map { |b| b[var]['value'] }
    out.concat(rows)
    break if rows.size < PAGE

    offset += PAGE
  end
  out
end

def post_delta(inserts)
  body = [{ 'inserts' => inserts, 'deletes' => [] }].to_json
  uri = URI(SEARCH_ENDPOINT)
  req = Net::HTTP::Post.new(uri)
  req['Content-Type'] = 'application/json'
  # The index is built for the 'public' group; without this header mu-search
  # has no group to update and the delta is a no-op.
  req['mu-auth-allowed-groups'] = ALLOWED_GROUPS
  req.body = body
  res = Net::HTTP.start(uri.hostname, uri.port, read_timeout: 600) { |http| http.request(req) }
  return if (200..299).include?(res.code.to_i)

  raise "search /update #{res.code}: #{res.body.to_s[0, 300]}"
end

scope = scope_clause(bestuurseenheid)
date  = date_clause(from_date)

label = bestuurseenheid.empty? ? 'ALL bestuurseenheden' : bestuurseenheid
label += " from #{from_date}" unless from_date.empty?
puts "Reindex scope: #{label}"
puts "Triplestore:   #{SPARQL_ENDPOINT}"
puts "mu-search:     #{SEARCH_ENDPOINT} (groups: #{ALLOWED_GROUPS})"
puts 'Querying sessions + agenda items...'

session_uris = fetch_uris("#{scope}\n#{date}", 'z')
agenda_uris  = fetch_uris("#{scope}\n?z besluit:behandelt ?ai .\n#{date}", 'ai')
puts "Found #{session_uris.size} sessions and #{agenda_uris.size} agenda items."

docs = session_uris.map { |u| [u, ZITTING_TYPE] } +
       agenda_uris.map  { |u| [u, AGENDAPUNT_TYPE] }

if docs.empty?
  puts 'Nothing to reindex for this scope.'
  exit 0
end

posted = 0
docs.each_slice(BATCH) do |slice|
  inserts = slice.map do |(subject, type)|
    {
      'subject'   => { 'type' => 'uri', 'value' => subject },
      'predicate' => { 'type' => 'uri', 'value' => TYPE_PRED },
      'object'    => { 'type' => 'uri', 'value' => type }
    }
  end
  post_delta(inserts)
  posted += slice.size
  puts "Pushed #{posted}/#{docs.size} documents to mu-search..."
  sleep THROTTLE
end

puts "Done. mu-search will (re)index #{docs.size} documents; allow a few seconds to settle."
puts 'Verify with your search count query, and check `docker compose logs -f search`.'
