import { BATCH_SIZE, ENDPOINT, SLEEP_BETWEEN_BATCHES } from "./config.js";

export function toStatements(termObjects) {
  return termObjects.map((o) => `${o.subject} ${o.predicate} ${o.object} .`);
}

export async function batchedUpdate(
  lib,
  statements,
  graph,
  operation,
  extraHeaders = {},
  batchSize = BATCH_SIZE,
) {
  const { muAuthSudo, chunk, sparqlEscapeUri } = lib;
  for (const batch of chunk(statements, batchSize)) {
    try {
      await muAuthSudo.updateSudo(
        `${operation} DATA {
          GRAPH ${sparqlEscapeUri(graph)} {
            ${batch.join("\n")}
          }
        }`,
        extraHeaders,
        { sparqlEndpoint: ENDPOINT, mayRetry: true },
      );
      await new Promise((resolve) =>
        setTimeout(resolve, SLEEP_BETWEEN_BATCHES),
      );
    } catch (error) {
      const smallerBatchSize = Math.floor(batchSize / 2);
      if (smallerBatchSize === 0) {
        console.error(`${operation} failed for:`, batch);
        throw error;
      }
      console.warn(
        `${operation} of ${batch.length} triples failed, retrying in batches of ${smallerBatchSize}`,
        error,
      );
      await batchedUpdate(
        lib,
        batch,
        graph,
        operation,
        extraHeaders,
        smallerBatchSize,
      );
    }
  }
}
