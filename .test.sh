#!/bin/sh

CONNINFO=`jq '.sqlServer.connString' ${1}`
UNQUOTED=`echo $CONNINFO | xargs`

dub build --build=unittest &&
psql -f .test_pgator_rpc_table.sql "$UNQUOTED" &&
./pgator --config=${1} --debug=true