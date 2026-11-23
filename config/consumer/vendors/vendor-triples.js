// Loket's stream also contains the vendors' credentials (muAccount:key,
// muAccount:keyHash): only these predicates are stored.

export const VENDORS_GRAPH =
  process.env.VENDORS_GRAPH || "http://mu.semte.ch/graphs/vendors";
const BATCH_SIZE = parseInt(process.env.BATCH_SIZE || 100);

const ALLOWED_PREDICATES = new Set([
  "<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>",
  "<http://mu.semte.ch/vocabularies/core/uuid>",
  "<http://xmlns.com/foaf/0.1/name>",
  "<http://mu.semte.ch/vocabularies/account/canActOnBehalfOf>",
]);

export function allowedTriples(termObjects, context) {
  const kept = termObjects.filter((o) => ALLOWED_PREDICATES.has(o.predicate));
  if (kept.length < termObjects.length) {
    console.log(
      `Skipping ${termObjects.length - kept.length} of ${termObjects.length} ${context} on predicates that aren't synced (e.g. credentials).`,
    );
  }
  return kept.map((o) => `${o.subject} ${o.predicate} ${o.object} .`);
}

export async function update(lib, operation, triples) {
  const { muAuthSudo, chunk, sparqlEscapeUri } = lib;
  for (const batch of chunk(triples, BATCH_SIZE)) {
    await muAuthSudo.updateSudo(
      `${operation} DATA {
        GRAPH ${sparqlEscapeUri(VENDORS_GRAPH)} {
          ${batch.join("\n")}
        }
      }`,
      {},
      { mayRetry: true },
    );
  }
}
