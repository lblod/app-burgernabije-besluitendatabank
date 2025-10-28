import {
  BYPASS_MU_AUTH_FOR_EXPENSIVE_QUERIES,
  DIRECT_DATABASE_ENDPOINT,
  MU_CALL_SCOPE_ID_INITIAL_SYNC,
  INGEST_GRAPH,
} from "./config";

const endpoint = BYPASS_MU_AUTH_FOR_EXPENSIVE_QUERIES
  ? DIRECT_DATABASE_ENDPOINT
  : process.env.MU_SPARQL_ENDPOINT;

/**
 * Dispatch the fetched information to a target graph.
 * @param { mu, muAuthSudo, fech } lib - The provided libraries from the host service.
 * @param { termObjects } data - The fetched quad information, which objects of serialized Terms
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
  const { insertIntoGraph } = lib;

  if (BYPASS_MU_AUTH_FOR_EXPENSIVE_QUERIES) {
    console.warn(`Service configured to skip MU_AUTH!`);
  }

  console.log(`Using ${endpoint} to insert triples`);
    await insertIntoGraph(data.termObjects, endpoint, INGEST_GRAPH, { "mu-call-scope-id": MU_CALL_SCOPE_ID_INITIAL_SYNC });

}

/**
 * A callback you can override to do extra manipulations
 *   after initial ingest.
 * @param { mu, muAuthSudo, fech } lib - The provided libraries from the host service.
 * @return {void} Nothing
 */
export async function onFinishInitialIngest(_) {
  console.log(`
    onFinishInitialIngest was called!
    Current implementation does nothing, no worries.
    You can overrule it for extra manipulations after initial ingest.
  `);
}

