#!/bin/bash
set -ve

CONNINFO=`jq '.sqlServer.connString' ${1}`
CONNINFO_UNQUOTED=`echo $CONNINFO | xargs`

dub build --build=unittest
psql -f .test_pgator_rpc_table.sql "$CONNINFO_UNQUOTED"

# Test calls table by preparing statements
`./pgator --config=${1} --debug=true --test=true; if [ $? -ne 2 ]; then exit 1; fi` # Some statements should be bad

# Start pgator server
./pgator --config=${1} --debug=true &
trap "kill %%" EXIT

ADDRESS=`jq '.listenAddresses[0]' ${1}`
ADDRESS_UNQUOTED=`echo $ADDRESS | xargs`
PORT=`jq '.listenPort' ${1}`

# Start test client
dub run pgator:test --build=unittest -- "$ADDRESS_UNQUOTED" "$PORT"
