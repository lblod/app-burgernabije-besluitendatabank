import { allowedTriples, update } from "./vendor-triples.js";

export async function dispatch(lib, data) {
  await update(lib, "INSERT", allowedTriples(data.termObjects, "triples"));
}
