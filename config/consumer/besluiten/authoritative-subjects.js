import {
  AUTHORITATIVE_GRAPHS,
  AUTHORITATIVE_SUBJECTS_ENDPOINT,
  AUTHORITATIVE_SUBJECTS_PAGE_SIZE,
  AUTHORITATIVE_SUBJECTS_TTL,
} from "./config.js";


let cache = new Set();
let loadedAt = 0;
let inFlight = null;


async function fetchSubjectsForGraph(lib, graph, subjects) {
  const { muAuthSudo, sparqlEscapeUri } = lib;
  let offset = 0;
  let rowsInPage;

  do {
    const query = `
      SELECT DISTINCT ?s WHERE {
        GRAPH ${sparqlEscapeUri(graph)} {
          ?s a ?type .
        }
        FILTER(isIRI(?s))
      }
      ORDER BY ?s
      LIMIT ${AUTHORITATIVE_SUBJECTS_PAGE_SIZE} OFFSET ${offset}
    `;
    const result = await muAuthSudo.querySudo(
      query,
      {},
      { sparqlEndpoint: AUTHORITATIVE_SUBJECTS_ENDPOINT, mayRetry: true },
    );

    const bindings = result.results.bindings;
    for (const binding of bindings) {
      subjects.add(sparqlEscapeUri(binding.s.value));
    }

    rowsInPage = bindings.length;
    // Advance by what we actually received rather than by the page size: virtuoso
    // silently truncates to ResultSetMaxRows if that is lower than our page size.
    offset += rowsInPage;
  } while (rowsInPage > 0);

  return offset;
}

async function reload(lib) {
  const start = Date.now();
  const subjects = new Set();

  for (const graph of AUTHORITATIVE_GRAPHS) {
    const rows = await fetchSubjectsForGraph(lib, graph, subjects);
    console.log(`Read ${rows} authoritative subjects from <${graph}>`);
  }

  cache = subjects;
  loadedAt = Date.now();
  console.log(
    `Authoritative subject cache holds ${cache.size} URIs (loaded in ${Date.now() - start}ms)`,
  );

  return cache;
}

export async function getAuthoritativeSubjects(lib) {
  if (loadedAt && Date.now() - loadedAt < AUTHORITATIVE_SUBJECTS_TTL) {
    return cache;
  }

  if (!inFlight) {
    inFlight = reload(lib).finally(() => {
      inFlight = null;
    });
  }

  try {
    return await inFlight;
  } catch (err) {
    if (!loadedAt) {
      console.error(
        `Could not load the authoritative subjects, refusing to ingest unfiltered.`,
      );
      throw err;
    }
    console.warn(
      `Could not refresh the authoritative subjects, falling back on the set loaded at ${new Date(loadedAt).toISOString()}`,
    );
    console.warn(err);
    return cache;
  }
}
