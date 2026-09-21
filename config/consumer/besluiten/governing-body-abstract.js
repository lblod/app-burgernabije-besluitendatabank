// Derives ext:governingBodyAbstract for everything that carries besluit:isGehoudenDoor.

import {
  BATCH_SIZE,
  BYPASS_MU_AUTH_FOR_EXPENSIVE_QUERIES,
  DIRECT_DATABASE_ENDPOINT,
  ENABLE_GOVERNING_BODY_ABSTRACT,
  GOVERNING_BODY_ABSTRACT_PREDICATE,
  GOVERNING_BODY_BACKFILL_PAGE_SIZE,
  GOVERNING_BODY_LOOKUP_ENDPOINT,
  GOVERNING_BODY_LOOKUP_GRAPHS,
  GOVERNING_BODY_SUBJECT_CHUNK_SIZE,
  INGEST_GRAPH,
  SLEEP_BETWEEN_BATCHES,
} from "./config.js";
import { batchedUpdate } from "./utils.js";

export const IS_GEHOUDEN_DOOR =
  "http://data.vlaanderen.be/ns/besluit#isGehoudenDoor";

const PREFIXES = `
PREFIX besluit: <http://data.vlaanderen.be/ns/besluit#>
PREFIX mandaat: <http://data.vlaanderen.be/ns/mandaat#>`;

const writeEndpoint = BYPASS_MU_AUTH_FOR_EXPENSIVE_QUERIES
  ? DIRECT_DATABASE_ENDPOINT
  : process.env.MU_SPARQL_ENDPOINT;

/**
 * The subjects of the isGehoudenDoor triples in a set of term objects, as escaped URIs.
 */
export function governingBodySubjects(termObjects, sparqlEscapeUri) {
  const predicate = sparqlEscapeUri(IS_GEHOUDEN_DOOR);
  return termObjects
    .filter((o) => o.predicate === predicate)
    .map((o) => o.subject);
}

function lookupGraphValues(sparqlEscapeUri) {
  return GOVERNING_BODY_LOOKUP_GRAPHS.map(sparqlEscapeUri).join(" ");
}

/**
 * Resolves ?subject -> ?abstract for every subject holding an isGehoudenDoor triple in the
 * ingest graph. `extraPatterns` is appended once both are bound, so it can filter on either.
 */
function derivationPattern(sparqlEscapeUri, extraPatterns = "") {
  return `
    GRAPH ${sparqlEscapeUri(INGEST_GRAPH)} { ?subject besluit:isGehoudenDoor ?body . }
    VALUES ?lookupGraph { ${lookupGraphValues(sparqlEscapeUri)} }
    {
      GRAPH ?lookupGraph { ?body mandaat:isTijdspecialisatieVan ?abstract . }
    }
    UNION
    {
      GRAPH ?lookupGraph { ?body a besluit:Bestuursorgaan . }
      FILTER NOT EXISTS { GRAPH ?specialisationGraph { ?body mandaat:isTijdspecialisatieVan ?otherAbstract . } }
      FILTER NOT EXISTS { GRAPH ?bindingGraph { ?body mandaat:bindingStart ?bindingStart . } }
      BIND(?body AS ?abstract)
    }
    ${extraPatterns}`;
}

async function select(lib, query) {
  const result = await lib.muAuthSudo.querySudo(
    query,
    {},
    { sparqlEndpoint: GOVERNING_BODY_LOOKUP_ENDPOINT, mayRetry: true },
  );
  return result.results.bindings;
}

function toTriples(bindings, sparqlEscapeUri) {
  const predicate = sparqlEscapeUri(GOVERNING_BODY_ABSTRACT_PREDICATE);
  return new Set(
    bindings.map(
      (binding) =>
        `${sparqlEscapeUri(binding.subject.value)} ${predicate} ${sparqlEscapeUri(binding.abstract.value)}.`,
    ),
  );
}

async function desiredTriples(lib, subjects) {
  const { sparqlEscapeUri } = lib;
  const bindings = await select(
    lib,
    `${PREFIXES}
    SELECT DISTINCT ?subject ?abstract WHERE {
      VALUES ?subject { ${subjects.join(" ")} }
      ${derivationPattern(sparqlEscapeUri)}
    }`,
  );
  return toTriples(bindings, sparqlEscapeUri);
}

async function currentTriples(lib, subjects) {
  const { sparqlEscapeUri } = lib;
  const bindings = await select(
    lib,
    `SELECT DISTINCT ?subject ?abstract WHERE {
      VALUES ?subject { ${subjects.join(" ")} }
      GRAPH ${sparqlEscapeUri(INGEST_GRAPH)} {
        ?subject ${sparqlEscapeUri(GOVERNING_BODY_ABSTRACT_PREDICATE)} ?abstract .
      }
    }`,
  );
  return toTriples(bindings, sparqlEscapeUri);
}

async function write(lib, triples, operation) {
  if (!triples.length) return;
  await batchedUpdate(
    lib,
    triples,
    INGEST_GRAPH,
    SLEEP_BETWEEN_BATCHES,
    BATCH_SIZE,
    {},
    writeEndpoint,
    operation,
  );
}

/**
 * Brings ext:governingBodyAbstract in sync for the given subjects.
 *
 * Call this *after* the changeset itself has been written: the derivation reads the
 * triplestore, so an isGehoudenDoor triple and the isTijdspecialisatieVan triple resolving
 * it are picked up even when they arrive in the same batch. Only the difference with what is
 * already stored is written, so unchanged subjects produce no deltas (and no search churn).
 *
 * @param { muAuthSudo, chunk, sparqlEscapeUri } lib - The provided libraries from the host service.
 * @param { string[] } subjects - Escaped subject URIs touched by isGehoudenDoor changes.
 */
export async function syncGoverningBodyAbstract(lib, subjects) {
  if (!ENABLE_GOVERNING_BODY_ABSTRACT || !subjects.length) return;

  const uniqueSubjects = [...new Set(subjects)];
  let inserted = 0;
  let deleted = 0;

  for (const chunkedSubjects of lib.chunk(
    uniqueSubjects,
    GOVERNING_BODY_SUBJECT_CHUNK_SIZE,
  )) {
    const desired = await desiredTriples(lib, chunkedSubjects);
    const current = await currentTriples(lib, chunkedSubjects);

    const toDelete = [...current].filter((triple) => !desired.has(triple));
    const toInsert = [...desired].filter((triple) => !current.has(triple));

    await write(lib, toDelete, "DELETE");
    await write(lib, toInsert, "INSERT");

    deleted += toDelete.length;
    inserted += toInsert.length;
  }

  if (inserted || deleted) {
    console.log(
      `Derived governing body: inserted ${inserted}, deleted ${deleted} ext:governingBodyAbstract triple(s) for ${uniqueSubjects.length} subject(s).`,
    );
  }
}

/**
 * Derives ext:governingBodyAbstract for every subject in the ingest graph that still misses
 * one, in pages. Used after an initial sync; scripts/backfill-governing-body-abstract.sh is
 * the equivalent for a store that is already ingested.
 *
 * Subjects whose governing body cannot be classified never make it into a page, so the loop
 * always terminates on a healthy store. If a page fails to shrink the backlog anyway (a write
 * that keeps landing in the dead letter file, say), we bail out rather than spin forever.
 */
export async function backfillGoverningBodyAbstract(lib) {
  if (!ENABLE_GOVERNING_BODY_ABSTRACT) return;

  const { sparqlEscapeUri } = lib;
  const query = `${PREFIXES}
    SELECT DISTINCT ?subject ?abstract WHERE {
      ${derivationPattern(
        sparqlEscapeUri,
        `FILTER NOT EXISTS {
        GRAPH ${sparqlEscapeUri(INGEST_GRAPH)} {
          ?subject ${sparqlEscapeUri(GOVERNING_BODY_ABSTRACT_PREDICATE)} ?abstract .
        }
      }`,
      )}
    }
    LIMIT ${GOVERNING_BODY_BACKFILL_PAGE_SIZE}`;

  let total = 0;
  let previousPage = null;
  let stalledPages = 0;

  for (;;) {
    const bindings = await select(lib, query);
    if (!bindings.length) break;

    const triples = [...toTriples(bindings, sparqlEscapeUri)];
    const page = triples.join("");
    if (page === previousPage) {
      if (++stalledPages >= 3) {
        console.warn(
          `Backfill of ext:governingBodyAbstract stalled on the same ${triples.length} triple(s) after ${total}; giving up. Check the dead letter file.`,
        );
        return;
      }
    } else {
      stalledPages = 0;
      previousPage = page;
    }

    await write(lib, triples, "INSERT");
    total += triples.length;
    console.log(`Backfilled ${total} ext:governingBodyAbstract triple(s).`);
  }

  console.log(
    `Backfill of ext:governingBodyAbstract finished, ${total} triple(s) derived.`,
  );
}
