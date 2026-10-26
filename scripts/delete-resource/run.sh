#!/bin/bash
mkdir -p /data/app/data/files
npm i
export DERIVED_FROM_URL=$1
MU_SPARQL_ENDPOINT=http://database:8890/sparql node app.mjs
