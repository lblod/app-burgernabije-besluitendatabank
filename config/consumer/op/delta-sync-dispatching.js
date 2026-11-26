import { INGEST_GRAPH } from "./config.js";
import { batchedUpdate, toStatements } from "./utils.js";
import { syncIdentifiers, touchesIdentifiers } from "./identifiers.js";

export async function dispatch(lib, data) {
  for (const { deletes, inserts } of data.termObjectChangeSets) {
    await batchedUpdate(lib, toStatements(deletes), INGEST_GRAPH, "DELETE");
    await batchedUpdate(lib, toStatements(inserts), INGEST_GRAPH, "INSERT");
    if (touchesIdentifiers(deletes) || touchesIdentifiers(inserts)) {
      await syncIdentifiers(lib, INGEST_GRAPH);
    }
  }
}
