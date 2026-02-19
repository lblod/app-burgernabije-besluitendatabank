const fs = require("fs");
const { DEAD_LETTER_FILE } = require("./config");

async function batchedUpdate(
  lib,
  nTriples,
  targetGraph,
  sleep,
  batch,
  extraHeaders,
  endpoint,
  operation,
) {
  const { muAuthSudo, chunk, sparqlEscapeUri } = lib;
  console.log(`Batch size: ${nTriples.length}`);

  const chunkedArray = chunk(nTriples, batch);
  let chunkCounter = 1;

  for (const chunkedTriple of chunkedArray) {
    console.log(
      `Processing chunk number ${chunkCounter} of ${chunkedArray.length} chunks.`,
    );
    try {
      const updateQuery = `
        ${operation} DATA {
           GRAPH ${sparqlEscapeUri(targetGraph)} {
             ${chunkedTriple.join("")}
           }
        }
      `;
      const connectOptions = { sparqlEndpoint: endpoint, mayRetry: true };
      await muAuthSudo.updateSudo(updateQuery, extraHeaders, connectOptions);
      await new Promise((r) => setTimeout(r, sleep));
    } catch (err) {
      // Binary backoff recovery.
      console.log(
        `Inserting the chunk failed for chunk size ${batch} and ${nTriples.length} triples`,
      );
      const smallerBatch = Math.floor(batch / 2);
      if (smallerBatch === 0) {
        writeToDeadLetterFile(chunkedTriple, targetGraph, operation, err);
      } else {
        console.log(`Retrying with chunk size of ${smallerBatch}`);
        await batchedUpdate(
          lib,
          chunkedTriple,
          targetGraph,
          sleep,
          smallerBatch,
          extraHeaders,
          endpoint,
          operation,
        );
      }
    }
    ++chunkCounter;
  }
}

function writeToDeadLetterFile(triples, targetGraph, operation, error) {
  const timestamp = new Date().toISOString();
  const entry = [
    `# ${timestamp} - ${operation} failed for graph <${targetGraph}>`,
    `# Error: ${error.message || error}`,
    ...triples,
    "",
  ].join("\n");

  console.warn(
    `Poison triple(s) detected, writing to dead letter file: ${DEAD_LETTER_FILE}`,
  );
  console.warn(`Failed triples: ${triples.join(" ")}`);
  fs.appendFileSync(DEAD_LETTER_FILE, entry);
}

module.exports = {
  batchedUpdate,
};
