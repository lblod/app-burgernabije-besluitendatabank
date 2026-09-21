#!/bin/bash

# Removes every triple using a denied predicate, straight on virtuoso. These predicates are
# not consumed anywhere in the stack, so no deltas are needed and mu-auth is bypassed.
#
# Runs read-only by default and reports what it would delete. Pass --apply to delete.
#
#   ./scripts/cleanup-denied-predicates.sh                 # report only
#   ./scripts/cleanup-denied-predicates.sh --apply          # delete, with a countdown
#   ./scripts/cleanup-denied-predicates.sh --apply --yes    # delete, no countdown
#
#   PREDICATES=<uri>[,<uri>...]  override the denylist (default matches the consumer's)
#   GRAPHS=<uri>[,<uri>...]      override graph discovery
#   BATCH_SIZE=100000            triples per DELETE statement
#
# Safe to interrupt and re-run: each batch is committed on its own and the loop simply
# picks up whatever is left.

set -euo pipefail
cd "$(dirname "$0")/.."

PREDICATES="${PREDICATES:-http://lblod.data.gift/vocabularies/besluit/extractedDecisionContent}"
BATCH_SIZE="${BATCH_SIZE:-100000}"
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

delete_batch () {
  printf 'SPARQL DEFINE sql:log-enable 3\nWITH <%s>\nDELETE { ?s <%s> ?o }\nWHERE { { SELECT ?s ?o WHERE { ?s <%s> ?o } LIMIT %s } };\nexit;\n' \
    "$1" "$2" "$2" "$BATCH_SIZE" | run_isql > /dev/null
}

count_triples () {
  local out
  out="$(printf 'SPARQL SELECT (COUNT(*) AS ?c) WHERE { GRAPH <%s> { ?s <%s> ?o } };\nexit;\n' "$1" "$2" \
    | run_isql | grep -E '^[0-9]+$' || true)"
  echo "${out%%$'\n'*}"
}

any_remaining () {
  local out
  out="$(printf 'SPARQL SELECT ?s WHERE { GRAPH <%s> { ?s <%s> ?o } } LIMIT 1;\nexit;\n' "$1" "$2" \
    | run_isql | grep -E '^[a-z]+://' || true)"
  [ -n "$out" ]
}

discover_graphs () {
  printf 'SPARQL SELECT DISTINCT ?g WHERE { GRAPH ?g { ?s <%s> ?o } };\nexit;\n' "$1" \
    | run_isql | grep -E '^[a-z]+://' || true
}

checkpoint () {
  printf "exec('checkpoint');\nexit;\n" | run_isql > /dev/null
}

for predicate in ${PREDICATES//,/ }; do
  echo "=== <$predicate>"

  if [ -n "$GRAPHS" ]; then
    graphs="${GRAPHS//,/ }"
  else
    echo "  discovering graphs (scans the predicate, can take a while on large stores)..."
    graphs="$(discover_graphs "$predicate")"
  fi

  if [ -z "${graphs// /}" ]; then
    echo "  not present in any graph, nothing to do"
    continue
  fi

  total=0
  for graph in $graphs; do
    n="$(count_triples "$graph" "$predicate")"
    n="${n:-0}"
    total=$((total + n))
    printf '  %12s  <%s>\n' "$n" "$graph"
  done
  echo "  total: $total"

  if [ "$APPLY" != true ]; then
    echo "  (report only, pass --apply to delete)"
    continue
  fi
  if [ "$total" -eq 0 ]; then
    continue
  fi

  if [ "$ASSUME_YES" != true ]; then
    echo "  deleting $total triples in ${BATCH_SIZE}-triple batches; ctrl-c within 5 seconds to abort"
    sleep 5
  fi

  for graph in $graphs; do
    if ! any_remaining "$graph" "$predicate"; then
      continue
    fi
    echo "  deleting from <$graph>"
    batch=0
    started=$(date +%s)
    while any_remaining "$graph" "$predicate"; do
      delete_batch "$graph" "$predicate"
      batch=$((batch + 1))
      printf '\r    batch %s (%ss elapsed)' "$batch" "$(( $(date +%s) - started ))"
    done
    printf '\r    %s batch(es) in %ss\n' "$batch" "$(( $(date +%s) - started ))"
    checkpoint
  done

  remaining=0
  for graph in $graphs; do
    n="$(count_triples "$graph" "$predicate")"
    remaining=$((remaining + ${n:-0}))
  done
  echo "  remaining after cleanup: $remaining"
done
