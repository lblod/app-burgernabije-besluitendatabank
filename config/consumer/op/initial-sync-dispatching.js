import { INGEST_GRAPH, MU_CALL_SCOPE_ID_INITIAL_SYNC } from "./config.js";
import { batchedUpdate, toStatements } from "./utils.js";
import { syncIdentifiers } from "./identifiers.js";

export async function dispatch(lib, data) {
  await batchedUpdate(
    lib,
    toStatements(data.termObjects),
    INGEST_GRAPH,
    "INSERT",
    { "mu-call-scope-id": MU_CALL_SCOPE_ID_INITIAL_SYNC },
  );
}

export async function onFinishInitialIngest(lib) {
  await syncIdentifiers(lib, INGEST_GRAPH);
}
