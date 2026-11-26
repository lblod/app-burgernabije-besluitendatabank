import { ENDPOINT } from "./config.js";

// The ACM/IDM login finds a bestuur by dcterms:identifier (vo_orgcode = OVO
// number), which OP doesn't publish; derive it from the OVO and KBO numbers.

const IDENTIFIER_PREDICATES = new Set([
  "<http://www.w3.org/ns/adms#identifier>",
  "<http://www.w3.org/2004/02/skos/core#notation>",
  "<https://data.vlaanderen.be/ns/generiek#gestructureerdeIdentificator>",
  "<https://data.vlaanderen.be/ns/generiek#lokaleIdentificator>",
]);

export function touchesIdentifiers(termObjects) {
  return termObjects.some((o) => IDENTIFIER_PREDICATES.has(o.predicate));
}

// Besturen without OP identifiers (ABB, added by a migration) are left alone.
export async function syncIdentifiers(lib, graph) {
  const { muAuthSudo, sparqlEscapeUri } = lib;
  const prefixes = `
    PREFIX adms: <http://www.w3.org/ns/adms#>
    PREFIX besluit: <http://data.vlaanderen.be/ns/besluit#>
    PREFIX dcterms: <http://purl.org/dc/terms/>
    PREFIX generiek: <https://data.vlaanderen.be/ns/generiek#>
    PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
  `;
  const g = sparqlEscapeUri(graph);
  const options = { sparqlEndpoint: ENDPOINT, mayRetry: true };

  await muAuthSudo.updateSudo(
    `${prefixes}
    DELETE {
      GRAPH ${g} { ?bestuurseenheid dcterms:identifier ?number . }
    }
    WHERE {
      GRAPH ${g} {
        ?bestuurseenheid a besluit:Bestuurseenheid ;
          adms:identifier ?anyIdentifier ;
          dcterms:identifier ?number .
        FILTER NOT EXISTS {
          ?bestuurseenheid adms:identifier ?identifier .
          ?identifier skos:notation ?notation ;
            generiek:gestructureerdeIdentificator/generiek:lokaleIdentificator ?current .
          FILTER(?notation IN ("OVO-nummer", "KBO nummer"))
          FILTER(STR(?current) = STR(?number))
        }
      }
    }`,
    {},
    options,
  );

  await muAuthSudo.updateSudo(
    `${prefixes}
    INSERT {
      GRAPH ${g} { ?bestuurseenheid dcterms:identifier ?number . }
    }
    WHERE {
      GRAPH ${g} {
        ?bestuurseenheid a besluit:Bestuurseenheid ;
          adms:identifier ?identifier .
        ?identifier skos:notation ?notation ;
          generiek:gestructureerdeIdentificator/generiek:lokaleIdentificator ?current .
        FILTER(?notation IN ("OVO-nummer", "KBO nummer"))
        BIND(STR(?current) AS ?number)
        FILTER NOT EXISTS { ?bestuurseenheid dcterms:identifier ?number . }
      }
    }`,
    {},
    options,
  );
  console.log(`Synced dcterms:identifier of the besturen in ${graph}`);
}
