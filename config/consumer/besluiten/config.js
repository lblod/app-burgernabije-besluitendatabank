const BATCH_SIZE = parseInt(process.env.BATCH_SIZE || 100);
const PARALLEL_CALLS = parseInt(process.env.PARALLEL_CALLS || 1);
const MU_CALL_SCOPE_ID_INITIAL_SYNC =
  process.env.MU_CALL_SCOPE_ID_INITIAL_SYNC ||
  "http://redpencil.data.gift/id/concept/muScope/deltas/consumer/initialSync";
const BYPASS_MU_AUTH_FOR_EXPENSIVE_QUERIES =
  process.env.BYPASS_MU_AUTH_FOR_EXPENSIVE_QUERIES == "true" ? true : false;
const DIRECT_DATABASE_ENDPOINT =
  process.env.DIRECT_DATABASE_ENDPOINT || "http://virtuoso:8890/sparql";
const MAX_DB_RETRY_ATTEMPTS = parseInt(process.env.MAX_DB_RETRY_ATTEMPTS || 5);
const SLEEP_BETWEEN_BATCHES = parseInt(
  process.env.SLEEP_BETWEEN_BATCHES || 1000,
);
const SLEEP_TIME_AFTER_FAILED_DB_OPERATION = parseInt(
  process.env.SLEEP_TIME_AFTER_FAILED_DB_OPERATION || 60000,
);
const INGEST_GRAPH =
  process.env.INGEST_GRAPH || `http://mu.semte.ch/graphs/public`;
const DEAD_LETTER_FILE =
  process.env.DEAD_LETTER_FILE || "/consumer-files/dead-letter-triples.nt";

const AUTHORITATIVE_GRAPHS = (
  process.env.AUTHORITATIVE_GRAPHS ||
  "http://mu.semte.ch/graphs/mandaten,http://mu.semte.ch/graphs/organisations"
)
  .split(",")
  .map((graph) => graph.trim())
  .filter((graph) => graph.length);
const ENABLE_AUTHORITATIVE_SUBJECT_FILTER =
  process.env.ENABLE_AUTHORITATIVE_SUBJECT_FILTER == "false" ? false : true;
const AUTHORITATIVE_SUBJECTS_TTL = parseInt(
  process.env.AUTHORITATIVE_SUBJECTS_TTL || 3600000,
);
const AUTHORITATIVE_SUBJECTS_PAGE_SIZE = parseInt(
  process.env.AUTHORITATIVE_SUBJECTS_PAGE_SIZE || 500000,
);

const AUTHORITATIVE_SUBJECTS_ENDPOINT =
  process.env.AUTHORITATIVE_SUBJECTS_ENDPOINT || DIRECT_DATABASE_ENDPOINT;

const DEFAULT_DENIED_PREDICATES = [
  "http://lblod.data.gift/vocabularies/besluit/extractedDecisionContent",
];
const DENIED_PREDICATES = (
  process.env.DENIED_PREDICATES
    ? process.env.DENIED_PREDICATES.split(",")
    : DEFAULT_DENIED_PREDICATES
)
  .map((predicate) => predicate.trim())
  .filter((predicate) => predicate.length);

export {
  BATCH_SIZE,
  PARALLEL_CALLS,
  MU_CALL_SCOPE_ID_INITIAL_SYNC,
  BYPASS_MU_AUTH_FOR_EXPENSIVE_QUERIES,
  DIRECT_DATABASE_ENDPOINT,
  MAX_DB_RETRY_ATTEMPTS,
  SLEEP_BETWEEN_BATCHES,
  SLEEP_TIME_AFTER_FAILED_DB_OPERATION,
  INGEST_GRAPH,
  DEAD_LETTER_FILE,
  AUTHORITATIVE_GRAPHS,
  ENABLE_AUTHORITATIVE_SUBJECT_FILTER,
  AUTHORITATIVE_SUBJECTS_TTL,
  AUTHORITATIVE_SUBJECTS_PAGE_SIZE,
  AUTHORITATIVE_SUBJECTS_ENDPOINT,
  DENIED_PREDICATES,
};
