import { updateSudo } from "@lblod/mu-auth-sudo";
const q = `PREFIX prov: <http://www.w3.org/ns/prov#>
DELETE WHERE {
graph ?g {
  ?s prov:wasDerivedFrom <${DERIVED_FROM_URL}>; ?p ?o.
}
}`;

async function main() {
  await updateSudo(q, {}, {});
}

main().then(() => {
  console.log("ok");
});
