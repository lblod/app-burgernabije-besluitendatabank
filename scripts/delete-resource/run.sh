#!/bin/bash
mkdir -p /data/app/data/files
npm i
# we bypass mu auth to avoid producing delta messages that could be consumed by the ldes consumer
export DERIVED_FROM_URL=$1
MU_SPARQL_ENDPOINT=http://database:8890/sparql node app.mjs
