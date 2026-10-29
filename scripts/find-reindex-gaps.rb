#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Report which bestuurseenheden (municipalities) have sessions in the triplestore
# that are missing from the mu-search index -- i.e. which ones need a reindex.
#
# It compares, per werkingsgebied (the index's `search_location_id`):
#   - the triplestore session count (one SPARQL GROUP BY query)
#   - the mu-search index session count (one count query per location; mu-search
#     has no aggregation, so this is N small queries)
# and prints the bestuurseenheden where triplestore > index, biggest gap first.
#
# Run it INSIDE the search container (only Ruby stdlib is used):
#
#   docker compose exec -T search ruby - < scripts/find-reindex-gaps.rb              # all dates
#   docker compose exec -T search ruby - 2026-01-01 < scripts/find-reindex-gaps.rb   # only from a date
#
# Feed the printed labels into the reindex script, e.g.:
#   docker compose exec -T search ruby - Asse 2026-01-01 < scripts/reindex-search.rb
#
# Env overrides (defaults assume it runs inside the search container):
#   SPARQL_ENDPOINT  default http://triplestore:8890/sparql
#   SEARCH_ENDPOINT  default http://localhost   (mu-search itself, port 80)
#   ALLOWED_GROUPS   default [{"variables":[],"name":"public"}]

require 'net/http'
require 'json'
require 'uri'

SPARQL_ENDPOINT = ENV.fetch('SPARQL_ENDPOINT', 'http://triplestore:8890/sparql')
SEARCH_ENDPOINT = ENV.fetch('SEARCH_ENDPOINT', 'http://localhost')
ALLOWED_GROUPS  = ENV.fetch('ALLOWED_GROUPS', '[{"variables":[],"name":"public"}]')

from_date = (ARGV[0] || '').strip

def sparql_select(query)
  uri = URI(SPARQL_ENDPOINT)
  req = Net::HTTP::Post.new(uri)
  req.set_form_data('query' => query, 'format' => 'application/sparql-results+json')
  req['Accept'] = 'application/sparql-results+json'
  res = Net::HTTP.start(uri.hostname, uri.port, read_timeout: 600) { |http| http.request(req) }
  raise "SPARQL #{res.code}: #{res.body.to_s[0, 300]}" unless res.code.to_i == 200

  JSON.parse(res.body)['results']['bindings']
end

# mu-search session count for one location (search_location_id), same date scope.
def index_count(loc_uuid, from_date)
  # NB: mu-search returns HTTP 500 for page[size]=0, so request 1 and read `count`.
  params = ['page[size]=1', "filter[:terms:search_location_id]=#{URI.encode_www_form_component(loc_uuid)}"]
  unless from_date.empty?
    q = URI.encode_www_form_component("planned_start:[#{from_date} TO *]")
    params << "filter[:query:planned_start]=#{q}"
  end
  uri = URI("#{SEARCH_ENDPOINT}/sessions/search?#{params.join('&')}")
  req = Net::HTTP::Get.new(uri)
  req['mu-auth-allowed-groups'] = ALLOWED_GROUPS
  res = Net::HTTP.start(uri.hostname, uri.port, read_timeout: 120) { |http| http.request(req) }
  return 0 unless res.code.to_i == 200

  body = JSON.parse(res.body)
  (body['count'] || 0).to_i
rescue StandardError
  0
end

date_filter =
  if from_date.empty?
    ''
  else
    %(?z besluit:geplandeStart ?start . FILTER(?start >= "#{from_date}T00:00:00+00:00"^^xsd:dateTime))
  end

query = <<~SPARQL
  PREFIX besluit: <http://data.vlaanderen.be/ns/besluit#>
  PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
  PREFIX mandaat: <http://data.vlaanderen.be/ns/mandaat#>
  PREFIX mu: <http://mu.semte.ch/vocabularies/core/>
  PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
  SELECT ?label ?loc (COUNT(DISTINCT ?z) AS ?c) WHERE {
    ?ee a besluit:Bestuurseenheid ; skos:prefLabel ?label ; besluit:werkingsgebied ?wg .
    ?wg mu:uuid ?loc .
    ?bo besluit:bestuurt ?ee .
    ?org (mandaat:isTijdspecialisatieVan?) ?bo .
    ?z besluit:isGehoudenDoor ?org .
    #{date_filter}
  } GROUP BY ?label ?loc ORDER BY ?label
SPARQL

scope = from_date.empty? ? 'all dates' : "from #{from_date}"
puts "Comparing triplestore vs mu-search session counts per bestuurseenheid (#{scope})..."

rows = sparql_select(query)
puts "Triplestore returned #{rows.size} bestuurseenheden. Checking the index..."

gaps = []
rows.each do |b|
  label = b['label']['value']
  loc   = b['loc']['value']
  ts    = b['c']['value'].to_i
  idx   = index_count(loc, from_date)
  gaps << { label: label, ts: ts, idx: idx, gap: ts - idx } if ts > idx
end

gaps.sort_by! { |g| -g[:gap] }

if gaps.empty?
  puts 'No gaps found: every bestuurseenheid is fully indexed for this scope.'
  exit 0
end

puts
printf("%-45s %8s %8s %8s\n", 'Bestuurseenheid', 'store', 'index', 'missing')
puts '-' * 73
gaps.each { |g| printf("%-45s %8d %8d %8d\n", g[:label][0, 45], g[:ts], g[:idx], g[:gap]) }
puts
puts "#{gaps.size} bestuurseenheden need a reindex; total missing sessions: #{gaps.sum { |g| g[:gap] }}."
puts 'Reindex them with scripts/reindex-search.rb (per label), e.g.:'
gaps.first(5).each { |g| puts %(  docker compose exec -T search ruby - "#{g[:label]}" #{from_date} < scripts/reindex-search.rb) }
