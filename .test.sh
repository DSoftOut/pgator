#!/bin/sh

dub build --build=unittest

CONNINFO=`jq '.sqlServer.connString' ${1}`
UNQUOTED=`echo $CONNINFO | xargs`

psql -f .test_pgator_rpc_table.sql "$UNQUOTED"

./pgator --config=${1} --debug=true
