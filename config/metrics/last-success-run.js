import promClient from 'prom-client';
import { sparqlEscapeUri } from 'mu';
import { querySudo as query } from '@lblod/mu-auth-sudo';
const  lastDeltaGauge = new promClient.Gauge({
  name: 'delta_sync_last_success_timestamp',
  help: 'Timestamp of the last successful job run as UNIX timestamp',
  labelNames: ['job_creator']
});
const register = promClient.register;

const creatorQuery = `
PREFIX dct: <http://purl.org/dc/terms/>
PREFIX cogs: <http://vocab.deri.ie/cogs#>
SELECT distinct ?creator WHERE {
    ?job a cogs:Job.
    ?job dct:creator ?creator
}
`;

async function lastSuccessTimeStampForCreator(creator) {
  const lastTimestampQuery = `
 PREFIX mu: <http://mu.semte.ch/vocabularies/core/>
  PREFIX task: <http://redpencil.data.gift/vocabularies/tasks/>
  PREFIX dct: <http://purl.org/dc/terms/>
  PREFIX prov: <http://www.w3.org/ns/prov#>
  PREFIX nie: <http://www.semanticdesktop.org/ontologies/2007/01/19/nie#>
  PREFIX ext: <http://mu.semte.ch/vocabularies/ext/>
  PREFIX oslc: <http://open-services.net/ns/core#>
  PREFIX cogs: <http://vocab.deri.ie/cogs#>
  PREFIX adms: <http://www.w3.org/ns/adms#>
  PREFIX nfo: <http://www.semanticdesktop.org/ontologies/2007/03/22/nfo#>
  PREFIX dbpedia: <http://dbpedia.org/resource/>

  SELECT DISTINCT ?deltaTimestamp WHERE {
      ?job a ?jobType ;
        task:operation ?operation;
        dct:creator ${sparqlEscapeUri(creator)}.

      ?task a ?tt;
        dct:isPartOf ?job;
        adms:status <http://redpencil.data.gift/id/concept/JobStatus/success>;
        dct:modified ?modified;
        task:operation ?op ;
        task:resultsContainer ?resultsContainer.

      ?resultsContainer a ?ct;
        dct:subject <http://redpencil.data.gift/id/concept/DeltaSync/DeltafileInfo>;
        ext:hasDeltafileTimestamp ?deltaTimestamp.

    }
    ORDER BY DESC(?deltaTimestamp)
limit 1
`;
  const response = await query(lastTimestampQuery);
  if (response.results?.bindings && response.results?.bindings.length == 1 ) {
    return response.results.bindings[0].deltaTimestamp.value;
  }
}

async function updateLastSuccessTimestamp() {
  let response = await query(creatorQuery);
  if (response.results?.bindings) {
    const creators = response.results.bindings.map(x => x.creator.value);
    for (const creator of creators) {
      const isoTimestamp = await lastSuccessTimeStampForCreator(creator);
      if (isoTimestamp) {
        const timestamp = Math.floor(new Date(isoTimestamp).getTime() / 1000); // Convert to seconds
        lastDeltaGauge.labels(creator).set(timestamp);
      }
    }
  }

}

export default {
  name: 'last delta sync',
  cronPattern: '*/2 * * * *',
  async cronExecute() {
    await updateLastSuccessTimestamp();
  },
  async metrics() {
//    return await register.metrics();
  }
};
