# Mock login sample data (dev only)

Mock users to try the validation reports per group (see the groups in
`config/authorization/config.lisp`) with the mock login, without ACM/IDM.
Never load this on production.

| Migration | Users | Role | Sees the validation reports of |
|---|---|---|---|
| `20261119170000-mock-user-abb` | Agentschap Binnenlands Bestuur | `LokaalBeslist-ABB` | every bestuur |
| `20261119170100-mock-users-suppliers` | one per vendor in `graphs/vendors` | `LokaalBeslist-leverancier` | the besturen of the vendor |
| `20261119170200-mock-users-gemeenten` | one per gemeente ("Gemeente Aalst", ...) | `LokaalBeslist-bestuur` | its own gemeente |

As in app-data-monitoring, every mock user (`foaf:Person` + `foaf:OnlineAccount`)
is stored twice:

- in the graph of its bestuur (`organizations/<uuid>`), where the mock login
  service finds it;
- in the public graph, so the frontend's mock login page (`/mock-login`) can
  list and search them (`/accounts?include=user`). The public account also has
  `ext:mockLoginGroupId`: the uuid of the bestuur to log in with. A bestuur can
  have other `mu:uuid`s in other graphs (harvested data); the mock login only
  accepts the one in the organisations graph.

A supplier logs in with one of the vendor's besturen. Only its copy in the graph
of that bestuur says it's a member of the vendor (`foaf:member`), which is what
the supplier group looks for.

The other samples:

- `20261119150100-sample-vendor`: "Voorbeeldleverancier", serving Zaventem and
  Londerzeel. It must run before the supplier users.
- `20261119150500-sample-evaluation-to-zaventem`: moves the sample validation
  report (`../20261119120000-sample-validation-report.*`) to the evaluation
  graph of Zaventem, linked to its latest gemeenteraad zitting. ABB, Zaventem
  and the supplier see it, Londerzeel doesn't.

## Load

The besturen come from the `organisations` graph, so the OP consumer must have
synced first.

```sh
cp config/sample-migrations/20261119120000-sample-validation-report.* config/migrations/local/
cp config/sample-migrations/mock-login/*.sparql config/migrations/local/
docker compose restart migrations
```

The supplier users are created for the vendors present when the migration
runs. To add users for vendors synced later, remove the migration's record
from `<http://mu.semte.ch/application>` and restart `migrations`.

## Log in

In the frontend (development build): **Aanmelden (mock)** in the header, or
`/mock-login`. Or with curl, using the account id and its
`mock-login-group-id`:

```sh
curl -s -g 'http://localhost/accounts?filter[user][family-name]=Zaventem'

curl -c jar -b jar -X POST http://localhost/mock/sessions \
  -H 'Content-Type: application/vnd.api+json' \
  -d '{"data":{"type":"sessions","relationships":{
        "account":{"data":{"type":"accounts","id":"<account id>"}},
        "group":{"data":{"type":"groups","id":"<mock-login-group-id>"}}}}}'

curl -b jar http://localhost/validation-reports
curl -b jar -X DELETE http://localhost/mock/sessions/current
```
