import { BYPASS_MU_AUTH_FOR_EXPENSIVE_QUERIES,
  DIRECT_DATABASE_ENDPOINT,
  BATCH_SIZE,
  SLEEP_BETWEEN_BATCHES,
  INGEST_GRAPH,
  ENABLE_AUTHORITATIVE_SUBJECT_FILTER,
} from './config.js';
import { batchedUpdate, rejectDeniedPredicates } from './utils.js';
import { getAuthoritativeSubjects } from './authoritative-subjects.js';
import { governingBodySubjects, syncGoverningBodyAbstract } from './governing-body-abstract.js';
const endpoint = BYPASS_MU_AUTH_FOR_EXPENSIVE_QUERIES ? DIRECT_DATABASE_ENDPOINT : process.env.MU_SPARQL_ENDPOINT;

/**
 * Dispatch the fetched information to a target graph.
 * @param { mu, muAuthSudo, fetch } lib - The provided libraries from the host service.
 * @param { termObjectChangeSets: { deletes, inserts } } data - The fetched changes sets, which objects of serialized Terms
 *          [ {
 *              graph: "<http://foo>",
 *              subject: "<http://bar>",
 *              predicate: "<http://baz>",
 *              object: "<http://boom>^^<http://datatype>"
 *            }
 *         ]
 * @return {void} Nothing
 */
export async function dispatch(lib, data) {
  const { termObjectChangeSets } = data;

  const authoritativeSubjects = ENABLE_AUTHORITATIVE_SUBJECT_FILTER
    ? await getAuthoritativeSubjects(lib)
    : null;

  for (let { deletes, inserts } of termObjectChangeSets) {

    if (BYPASS_MU_AUTH_FOR_EXPENSIVE_QUERIES) {
      console.warn(`Service configured to skip MU_AUTH!`);
    }

    const deleteStatements = deletes.map(o => `${o.subject} ${o.predicate} ${o.object}.`);
    await batchedUpdate(
      lib,
      deleteStatements,
      INGEST_GRAPH,
      SLEEP_BETWEEN_BATCHES,
      BATCH_SIZE,
      {},
      endpoint,
      "DELETE",
    );

    const allowedInserts = rejectDeniedPredicates(inserts, lib.sparqlEscapeUri, "inserts");

    const keptInserts = authoritativeSubjects
      ? allowedInserts.filter(o => !authoritativeSubjects.has(o.subject))
      : allowedInserts;
    if (keptInserts.length < allowedInserts.length) {
      console.log(`Skipping ${allowedInserts.length - keptInserts.length} of ${allowedInserts.length} inserts about subjects managed by an authoritative source.`);
    }

    const insertStatements = keptInserts.map(o => `${o.subject} ${o.predicate} ${o.object}.`);
    await batchedUpdate(
      lib,
      insertStatements,
      INGEST_GRAPH,
      SLEEP_BETWEEN_BATCHES,
      BATCH_SIZE,
      {},
      endpoint,
      "INSERT",
    );

    await syncGoverningBodyAbstract(lib, [
      ...governingBodySubjects(deletes, lib.sparqlEscapeUri),
      ...governingBodySubjects(keptInserts, lib.sparqlEscapeUri),
    ]);
  }
}
