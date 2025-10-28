import { BYPASS_MU_AUTH_FOR_EXPENSIVE_QUERIES,
  DIRECT_DATABASE_ENDPOINT,
  INGEST_GRAPH,
} from './config';
const endpoint = BYPASS_MU_AUTH_FOR_EXPENSIVE_QUERIES ? DIRECT_DATABASE_ENDPOINT : process.env.MU_SPARQL_ENDPOINT; //Defaults to mu-auth


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
    const { insertIntoGraph, deleteFromGraph } = lib;

  for (let { deletes, inserts } of termObjectChangeSets) {

    if (BYPASS_MU_AUTH_FOR_EXPENSIVE_QUERIES) {
      console.warn(`Service configured to skip MU_AUTH!`);
    }
    console.log(`Using ${endpoint} to insert triples`);

    await deleteFromGraph(deletes, endpoint, INGEST_GRAPH, {});
    await insertIntoGraph(inserts, endpoint, INGEST_GRAPH, {});

  }
}

