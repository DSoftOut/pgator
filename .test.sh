#!/bin/sh
set -ve

CONNINFO=`jq '.sqlServer.connString' ${1}`
UNQUOTED=`echo $CONNINFO | xargs`

#~ dub build --build=unittest
#~ psql -f .test_pgator_rpc_table.sql "$UNQUOTED"
#~ ./pgator --config=${1} --debug=true --test=true || true
#~ ./pgator --config=${1} --debug=true

ADDRESS=`jq '.listenAddresses[0]' ${1}`
PORT=`jq '.listenPort' ${1}`

dub run pgator:test --build=unittest-cov -- "$ADDRESS" "$PORT"
