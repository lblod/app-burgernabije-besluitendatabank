import { updateSudo, querySudo } from "@lblod/mu-auth-sudo";

const agendaPointId = (process.env.DERIVED_FROM_URL || "").trim();
if (!agendaPointId) {
  console.log("please provide an agenda point id to delete");
  process.exit(-1);
}

const BATCH_SIZE = 5;

async function deleteDerivedBatched(agendaPoint, derived) {
    await updateSudo(`DELETE WHERE {graph ?g {<${agendaPoint}> ?p ?o}}`, {}, {});


  while (true) {
    const selectQuery = `
      PREFIX prov: <http://www.w3.org/ns/prov#>
      SELECT DISTINCT ?s ?p WHERE {
          ?s prov:wasDerivedFrom <${derived}>; ?p ?o.
      } LIMIT ${BATCH_SIZE}
    `;

    const result = await querySudo(selectQuery);
    const bindings = result.results.bindings;

    if (!bindings.length) {
      console.log("nothing to delete with derived", derived);
      break;
    }

    for (const {s, p} of bindings.map((b) => {return {s: b.s.value, p: b.p.value}})) {
      const deleteQuery = `
          DELETE WHERE {
            GRAPH ?g {
              <${s}> <${p}> ?o.
            }
          } 
        `;
      await updateSudo(deleteQuery, {}, {mayRetry: true});
    }

    if (bindings.length < BATCH_SIZE) {
      break;
    }
  }

  console.log(`finished deleting derived from ${derived}`);
}

async function main() {
  const derivedFromBindings = await querySudo(`
    PREFIX prov: <http://www.w3.org/ns/prov#>
    PREFIX mu: <http://mu.semte.ch/vocabularies/core/>
    SELECT ?s ?derived WHERE {
      ?s mu:uuid "${agendaPointId.trim()}".
      ?s prov:wasDerivedFrom ?derived.
    }
  `);

  if (derivedFromBindings.results.bindings.length) {
    for (const derivedRes of derivedFromBindings.results.bindings) {
      const derived = derivedRes.derived.value;
      const agendaPoint = derivedRes.s.value;
      console.log("deleting derived from", derived);
      await deleteDerivedBatched(agendaPoint,derived);
    }
  } else {
    console.log("no bindings");
  }
}

main().then(() => {
  console.log("ok");
});
