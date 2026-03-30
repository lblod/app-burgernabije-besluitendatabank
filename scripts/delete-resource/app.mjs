import { updateSudo } from "@lblod/mu-auth-sudo";
const derived = (process.env.DERIVED_FROM_URL || '').trim();
if(!derived) {
	console.log("please provide an url to delete (the url the agenda point was derived from)");
	process.exit(-1);
}
const q = `PREFIX prov: <http://www.w3.org/ns/prov#>
DELETE WHERE {
graph ?g {
  ?s prov:wasDerivedFrom <${derived}>.
  ?s ?p ?o.
}}`;

async function main() {
  await updateSudo(q, {}, {});
}

main().then(() => {
  console.log("ok");
});