#!/bin/bash
set -ve
shopt -s huponexit

CONNINFO=`jq '.sqlServer.connString' ${1}`
CONNINFO_UNQUOTED=`echo $CONNINFO | xargs`

dub build --build=unittest
psql -f .test_pgator_rpc_table.sql "$CONNINFO_UNQUOTED"
./pgator --config=${1} --debug=true --test=true || true #TODO: check exitcode==1
./pgator --config=${1} --debug=true &

ADDRESS=`jq '.listenAddresses[0]' ${1}`
ADDRESS_UNQUOTED=`echo $ADDRESS | xargs`
PORT=`jq '.listenPort' ${1}`

dub run pgator:test --build=unittest-cov -- "$ADDRESS_UNQUOTED" "$PORT" || true
