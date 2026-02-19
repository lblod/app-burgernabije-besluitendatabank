# Changelog

## Unreleased

## 1.4.0 (2026-02-19)
### :bug: Bug fixes
- Fixed delta config, notify search on all changes
- Simplified delta handling and added logic to skip failing triples

### :arrow_up: Dependency updates
- delta notifier bumped to nvdk/mu-delta-notifier:1.1.0 (was semtech/mu-delta-notifier:0.4.0)

### :house: Infrastructure & configuration
- fold changeSets in deltanotifier before sending to search
- only send matching triples to uuid service to limit delta size
- removed error-alert and deliver email service as these weren't used

## 1.3.0 (2026-02-09)
### :bug: Bug fixes
- Fix sparql-parser configuration

### :arrow_up: Dependency updates
- Bump frontend to v0.8.10
- Bump mu-search to v0.12.0

## 1.2.0 (2026-02-02)

### :rocket: Features
- Add inverse relation on governing body classification code
- Add import script for data loading (with support for compressed distributions)
- Set up basic metrics (monitoring)
- Enable analyzer for search content field
- Set up separate graphs for consumers
- Migrate `semtech/mu-authorization` to `semtech/sparql-parser`

### :bug: Bug fixes
- Remove broken link from frontend to identifier
- Fix service name in production docker-compose
- Remove unused clean group from search config

### :house: Infrastructure & configuration
- Limit mu-search memory usage
- Tweak Elasticsearch configuration
- Update docker-compose for initial sync performance optimizations
- Increase memory allocation settings in virtuoso.ini
- Update besluiten harvester links to production data
- Add links to sparql endpoints of besluiten harvester QA
- Remove deprecated version from docker-compose files
- Remove unused search properties

### :arrow_up: Dependency updates
- Bump frontend from v0.8.0 to v0.8.9
- Bump mu-search to v0.11.0
- Bump sparql-parser to v0.0.15
- Bump Virtuoso to v1.3.0
- Bump mu-cl-resources to v1.25.0

### :memo: Documentation
- Add setup instructions for local development environment
- Update README

## 1.1.0 (2024-03-27)

### :rocket: Features
- Add session type and mappings to search configuration
- Add logs to governing body report generation

### :bug: Bug fixes
- Change alternate-link typing to string-set

### :arrow_up: Dependency updates
- Bump frontend to v0.8.0
- Bump report-generation to loket-report-generation-service v0.8.0

### :memo: Documentation
- Fix bestuursorganen report generation schedule documentation

## 1.0.0 (2024-02-19)
### :sunrise: Show ourselves to the world
- initial release!
