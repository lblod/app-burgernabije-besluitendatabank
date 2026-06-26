#!/bin/bash
# frozen_string_literal: false
#
# Add an ElasticSearch field alias  search_theme_id -> resolution_themas.id.keyword
# to every live mu-search index that has a resolution_themas field (the
# agenda-items and sessions indexes).
#
# WHY: config/search/config.json declares `search_theme_id` as a copy_to target,
# but mu-search applies that mapping only when an index is CREATED. On an index
# built before the theme fields were added, search_theme_id never exists, so
# filter[:terms:search_theme_id]=... returns 0 -- even though the theme data IS
# present and filterable as resolution_themas.id.keyword (created by ES dynamic
# mapping). A field alias exposes that concrete field under the name the
# frontend already queries, with NO reindex and NO frontend change.
#
# This is filter-only (aliases are not stored in _source); that's exactly what
# this facet field is for. Theme display keeps using the resolution_themas /
# themas objects, which are in _source.
#
# Run on the host that runs this stack:
#   bash scripts/add-search-theme-alias.sh
#
# Idempotent: re-running is a no-op once the alias exists. Re-apply only if the
# index is ever deleted/rebuilt (after a full reset-elastic.sh the config.json
# copy_to mapping takes over and this alias is no longer needed).
#
# Env:
#   ES   ElasticSearch base URL as seen from the host
#        default: docker compose exec into the elasticsearch service on :9200

set -euo pipefail

ES_EXEC=(docker compose exec -T elasticsearch curl -s)
ES_BASE="http://localhost:9200"
TARGET="resolution_themas.id.keyword"
ALIAS="search_theme_id"

es() { "${ES_EXEC[@]}" "$@"; }

echo "Listing indexes..."
indexes=$(es "${ES_BASE}/_cat/indices?h=index" | tr -d '\r' | grep -v '^\.' | sort -u)

if [ -z "$indexes" ]; then
  echo "No indexes found. Is the elasticsearch service up?"
  exit 1
fi

applied=0
for idx in $indexes; do
  mapping=$(es "${ES_BASE}/${idx}/_mapping" || true)
  # Only touch indexes that actually have resolution_themas (agenda-items, sessions).
  echo "$mapping" | grep -q '"resolution_themas"' || { echo "  skip ${idx} (no resolution_themas)"; continue; }

  if echo "$mapping" | grep -q "\"${ALIAS}\""; then
    echo "  ${idx}: ${ALIAS} already present, skipping"
    continue
  fi

  echo "  ${idx}: adding alias ${ALIAS} -> ${TARGET}"
  resp=$(es -X PUT "${ES_BASE}/${idx}/_mapping" \
    -H 'Content-Type: application/json' \
    -d "{\"properties\":{\"${ALIAS}\":{\"type\":\"alias\",\"path\":\"${TARGET}\"}}}")
  echo "    -> ${resp}"
  echo "$resp" | grep -q '"acknowledged":true' && applied=$((applied + 1))
done

echo "Done. Aliases applied on ${applied} index(es)."
echo "Verify (public endpoint):"
echo "  curl -s 'http://localhost/search/agenda-items/search?page%5Bsize%5D=1&filter%5B%3Aterms%3Asearch_theme_id%5D=de069524-90e5-4b35-b68e-ede03c19911e' | grep -o '\"count\":[0-9]*'"
