#!/bin/bash

# Derives ext:governingBodyAbstract for existing data, straight on virtuoso.

set -euo pipefail
cd "$(dirname "$0")/.."

PREDICATE="${PREDICATE:-http://mu.semte.ch/vocabularies/ext/governingBodyAbstract}"
IS_GEHOUDEN_DOOR="http://data.vlaanderen.be/ns/besluit#isGehoudenDoor"
LOOKUP_GRAPHS="${LOOKUP_GRAPHS:-http://mu.semte.ch/graphs/mandaten,http://mu.semte.ch/graphs/organisations}"
BATCH_SIZE="${BATCH_SIZE:-25000}"
GRAPHS="${GRAPHS:-}"

APPLY=false
ASSUME_YES=false
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=true ;;
    --yes|-y) ASSUME_YES=true ;;
    *) echo "unknown argument: $arg" >&2; exit 64 ;;
  esac
done

run_isql () { docker compose exec -T triplestore isql-v 2>&1; }

# The graph holding the sessions is always consulted too: harvested data can carry the
# organisation triples itself, and on some instances it is the only place that has them.
lookup_values () {
  local values="<$1>"
  local graph
  for graph in ${LOOKUP_GRAPHS//,/ }; do
    [ "$graph" = "$1" ] || values="$values <$graph>"
  done
  echo "$values"
}

# Binds ?abstract for a ?body: its time specialisation, or the body itself when it is abstract.
#
# $2 says what the second branch does with the body it just classified, because that differs
# per caller and virtuoso is particular about it:
#   - producing a value      -> BIND(?body AS ?abstract)
#   - testing a known value  -> FILTER(?abstract = ?body); a BIND on an ?abstract bound outside
#                               the FILTER NOT EXISTS is treated as a fresh variable, so it
#                               constrains nothing
#   - testing any value      -> nothing at all; a BIND fails to compile when ?body itself is
#                               the external variable
classification_pattern () {
  cat <<PATTERN
    VALUES ?lookupGraph { $(lookup_values "$1") }
    { GRAPH ?lookupGraph { ?body mandaat:isTijdspecialisatieVan ?abstract . } }
    UNION
    {
      GRAPH ?lookupGraph { ?body a besluit:Bestuursorgaan . }
      FILTER NOT EXISTS { GRAPH ?sg { ?body mandaat:isTijdspecialisatieVan ?otherAbstract . } }
      FILTER NOT EXISTS { GRAPH ?bg { ?body mandaat:bindingStart ?bindingStart . } }
      ${2-}
    }
PATTERN
}

# Resolves ?subject -> ?abstract for the sessions in graph $1 that have no derived triple yet.
resolution_pattern () {
  cat <<PATTERN
    GRAPH <$1> { ?subject <$IS_GEHOUDEN_DOOR> ?body . }
$(classification_pattern "$1" 'BIND(?body AS ?abstract)')
    FILTER NOT EXISTS { GRAPH <$1> { ?subject <$PREDICATE> ?abstract . } }
PATTERN
}

# Derived triples in graph $1 that the data no longer supports: the session lost its
# isGehoudenDoor triple, or the body it points at now resolves elsewhere.
stale_pattern () {
  cat <<PATTERN
    GRAPH <$1> { ?subject <$PREDICATE> ?abstract . }
    FILTER NOT EXISTS {
      GRAPH <$1> { ?subject <$IS_GEHOUDEN_DOOR> ?body . }
$(classification_pattern "$1" 'FILTER(?abstract = ?body)')
    }
PATTERN
}

sparql_prefixes='PREFIX besluit: <http://data.vlaanderen.be/ns/besluit#>
PREFIX mandaat: <http://data.vlaanderen.be/ns/mandaat#>'

count_pending () {
  local out
  out="$(printf 'SPARQL %s\nSELECT (COUNT(*) AS ?c) WHERE { { SELECT DISTINCT ?subject ?abstract WHERE {\n%s\n} } };\nexit;\n' \
    "$sparql_prefixes" "$(resolution_pattern "$1")" | run_isql | grep -E '^[0-9]+$' || true)"
  echo "${out%%$'\n'*}"
}

# Sessions whose governing body we cannot classify: they keep needing the dual-path fallback.
count_unresolvable () {
  local out
  out="$(printf 'SPARQL %s\nSELECT (COUNT(DISTINCT ?subject) AS ?c) WHERE {\n  GRAPH <%s> { ?subject <%s> ?body . }\n  FILTER NOT EXISTS {\n%s\n  }\n};\nexit;\n' \
    "$sparql_prefixes" "$1" "$IS_GEHOUDEN_DOOR" "$(classification_pattern "$1")" \
    | run_isql | grep -E '^[0-9]+$' || true)"
  echo "${out%%$'\n'*}"
}

count_stale () {
  local out
  out="$(printf 'SPARQL %s\nSELECT (COUNT(*) AS ?c) WHERE { { SELECT DISTINCT ?subject ?abstract WHERE {\n%s\n} } };\nexit;\n' \
    "$sparql_prefixes" "$(stale_pattern "$1")" | run_isql | grep -E '^[0-9]+$' || true)"
  echo "${out%%$'\n'*}"
}

any_matching () {
  local out
  out="$(printf 'SPARQL %s\nSELECT ?subject WHERE {\n%s\n} LIMIT 1;\nexit;\n' \
    "$sparql_prefixes" "$2" | run_isql | grep -E '^[a-z]+://' || true)"
  [ -n "$out" ]
}

any_pending () { any_matching "$1" "$(resolution_pattern "$1")"; }
any_stale () { any_matching "$1" "$(stale_pattern "$1")"; }

derive_batch () {
  printf 'SPARQL DEFINE sql:log-enable 3\n%s\nINSERT { GRAPH <%s> { ?subject <%s> ?abstract . } }\nWHERE { { SELECT DISTINCT ?subject ?abstract WHERE {\n%s\n} LIMIT %s } };\nexit;\n' \
    "$sparql_prefixes" "$1" "$PREDICATE" "$(resolution_pattern "$1")" "$BATCH_SIZE" | run_isql > /dev/null
}

prune_batch () {
  printf 'SPARQL DEFINE sql:log-enable 3\n%s\nDELETE { GRAPH <%s> { ?subject <%s> ?abstract . } }\nWHERE { { SELECT DISTINCT ?subject ?abstract WHERE {\n%s\n} LIMIT %s } };\nexit;\n' \
    "$sparql_prefixes" "$1" "$PREDICATE" "$(stale_pattern "$1")" "$BATCH_SIZE" | run_isql > /dev/null
}

discover_graphs () {
  printf 'SPARQL SELECT DISTINCT ?g WHERE { GRAPH ?g { ?s <%s> ?o } };\nexit;\n' "$IS_GEHOUDEN_DOOR" \
    | run_isql | grep -E '^[a-z]+://' || true
}

checkpoint () {
  printf "exec('checkpoint');\nexit;\n" | run_isql > /dev/null
}

echo "=== deriving <$PREDICATE>"

if [ -n "$GRAPHS" ]; then
  graphs="${GRAPHS//,/ }"
else
  echo "  discovering graphs holding sessions (can take a while on large stores)..."
  graphs="$(discover_graphs)"
fi

if [ -z "${graphs// /}" ]; then
  echo "  no graph holds <$IS_GEHOUDEN_DOOR>, nothing to do"
  exit 0
fi

total=0
for graph in $graphs; do
  pending="$(count_pending "$graph")"
  pending="${pending:-0}"
  stale="$(count_stale "$graph")"
  stale="${stale:-0}"
  unresolvable="$(count_unresolvable "$graph")"
  total=$((total + pending + stale))
  printf '  %12s to derive, %s stale to prune, %s unclassifiable  <%s>\n' \
    "$pending" "$stale" "${unresolvable:-0}" "$graph"
done
echo "  total: $total"

if [ "$APPLY" != true ]; then
  echo "  (report only, pass --apply to write)"
  exit 0
fi
if [ "$total" -eq 0 ]; then
  exit 0
fi

if [ "$ASSUME_YES" != true ]; then
  echo "  writing $total triples in ${BATCH_SIZE}-subject batches; ctrl-c within 5 seconds to abort"
  sleep 5
fi

# Prune before deriving: a subject whose link moved gets its stale triple removed first, so
# the derivation that follows leaves it with exactly one value.
run_batches () { # graph, label, probe function, batch function
  if ! "$3" "$1"; then
    return 0
  fi
  echo "  $2 <$1>"
  local batch=0
  local started
  started=$(date +%s)
  while "$3" "$1"; do
    "$4" "$1"
    batch=$((batch + 1))
    printf '\r    batch %s (%ss elapsed)' "$batch" "$(( $(date +%s) - started ))"
  done
  printf '\r    %s batch(es) in %ss\n' "$batch" "$(( $(date +%s) - started ))"
  checkpoint
}

for graph in $graphs; do
  run_batches "$graph" "pruning stale triples from" any_stale prune_batch
  run_batches "$graph" "deriving into" any_pending derive_batch
done

remaining=0
for graph in $graphs; do
  n="$(count_pending "$graph")"
  remaining=$((remaining + ${n:-0}))
  n="$(count_stale "$graph")"
  remaining=$((remaining + ${n:-0}))
done
echo "  remaining after backfill: $remaining"
echo "  note: written straight to virtuoso, run ./scripts/reset-elastic.sh to get it into mu-search"
