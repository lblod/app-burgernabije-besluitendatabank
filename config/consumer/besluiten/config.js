export const MU_CALL_SCOPE_ID_INITIAL_SYNC =
  process.env.MU_CALL_SCOPE_ID_INITIAL_SYNC ||
  "http://redpencil.data.gift/id/concept/muScope/deltas/consumer/initialSync";
export const BYPASS_MU_AUTH_FOR_EXPENSIVE_QUERIES =
  process.env.BYPASS_MU_AUTH_FOR_EXPENSIVE_QUERIES == "true" ? true : false;
export const DIRECT_DATABASE_ENDPOINT =
  process.env.DIRECT_DATABASE_ENDPOINT || "http://virtuoso:8890/sparql";

export const INGEST_GRAPH =
  process.env.INGEST_GRAPH || `http://mu.semte.ch/graphs/public`;
