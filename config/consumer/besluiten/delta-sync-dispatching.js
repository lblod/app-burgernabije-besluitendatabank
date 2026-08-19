import { batchedUpdate, normalizeGeometries, hasLocnGeometry } from "./utils";
import {
  BYPASS_MU_AUTH_FOR_EXPENSIVE_QUERIES,
  DIRECT_DATABASE_ENDPOINT,
  MU_CALL_SCOPE_ID_INITIAL_SYNC,
  BATCH_SIZE,
  SLEEP_BETWEEN_BATCHES,
  INGEST_GRAPH,
} from "./config";

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
async function dispatch(lib, data) {
  const { termObjectChangeSets } = data;

  for (let { deletes, inserts } of termObjectChangeSets) {

    if (BYPASS_MU_AUTH_FOR_EXPENSIVE_QUERIES) {
      console.warn(`Service configured to skip MU_AUTH!`);
    }

    const deleteStatements = deletes.map(o => `${o.subject} ${o.predicate} ${o.object}.`);
    await batchedUpdate(
      lib,
      deleteStatements,
      null,
      SLEEP_BETWEEN_BATCHES,
      BATCH_SIZE,
      {},
      endpoint,
      "DELETE",
    );

    const insertStatements = inserts.map(o => `${o.subject} ${o.predicate} ${o.object}.`);
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

    if (hasLocnGeometry(inserts)) {
      await normalizeGeometries(lib);
    }
  }
}

export { dispatch };
