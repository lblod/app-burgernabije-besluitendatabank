import { allowedTriples, update } from "./vendor-triples.js";

export async function dispatch(lib, data) {
  for (const { deletes, inserts } of data.termObjectChangeSets) {
    await update(lib, "DELETE", allowedTriples(deletes, "deletes"));
    await update(lib, "INSERT", allowedTriples(inserts, "inserts"));
  }
}
