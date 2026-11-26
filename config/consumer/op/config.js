export const INGEST_GRAPH =
  process.env.INGEST_GRAPH || "http://mu.semte.ch/graphs/public";
export const BATCH_SIZE = parseInt(process.env.BATCH_SIZE) || 100;
export const SLEEP_BETWEEN_BATCHES =
  parseInt(process.env.SLEEP_BETWEEN_BATCHES) || 1000;
export const MU_CALL_SCOPE_ID_INITIAL_SYNC =
  process.env.MU_CALL_SCOPE_ID_INITIAL_SYNC ||
  "http://redpencil.data.gift/id/concept/muScope/deltas/consumer/initialSync";
const BYPASS_MU_AUTH_FOR_EXPENSIVE_QUERIES =
  process.env.BYPASS_MU_AUTH_FOR_EXPENSIVE_QUERIES == "true";
const DIRECT_DATABASE_ENDPOINT =
  process.env.DIRECT_DATABASE_ENDPOINT || "http://virtuoso:8890/sparql";
export const ENDPOINT = BYPASS_MU_AUTH_FOR_EXPENSIVE_QUERIES
  ? DIRECT_DATABASE_ENDPOINT
  : process.env.MU_SPARQL_ENDPOINT;
