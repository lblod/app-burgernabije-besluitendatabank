import { updateSudo, querySudo } from "@lblod/mu-auth-sudo";
const agendaPointId = (process.env.DERIVED_FROM_URL || '').trim();
if(!agendaPointId) {
	console.log("please provide an agenda point id to delete");
	process.exit(-1);
}
async function main() {

const derivedFromBindings = await querySudo(`
PREFIX prov: <http://www.w3.org/ns/prov#>
PREFIX mu: <http://mu.semte.ch/vocabularies/core/> 
SELECT ?derived WHERE {
  ?s mu:uuid "${agendaPointId.trim()}".
  ?s prov:wasDerivedFrom ?derived.
}
`);


if(derivedFromBindings.results.bindings.length) {
for(const derivedRes of derivedFromBindings.results.bindings) {
  const derived = derivedRes.derived.value;
  console.log('deleting derived from', derived);
  const q = `PREFIX prov: <http://www.w3.org/ns/prov#>
              PREFIX mu: <http://mu.semte.ch/vocabularies/core/>
              DELETE WHERE {
              graph ?g {
              ?x prov:wasDerivedFrom <${derived}>.
                ?x ?xp ?xo.
              }}`;
  await updateSudo(q, {}, {});

}
}else {
  console.log("no bindings");
}
}

main().then(() => {
  console.log("ok");
});