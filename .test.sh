#!/bin/bash
set -ve

#dub build --build=unittest
dub build --build=release

CONNINFO=`jq '.sqlServer.connString' ${1}`
CONNINFO_UNQUOTED=`echo $CONNINFO | xargs`

# Setup Postgres test scheme
psql -v ON_ERROR_STOP=ON -f .test_pgator_rpc_table.sql "$CONNINFO_UNQUOTED"

# Test calls table by preparing statements
set +e
./pgator --config=${1} --debug=true --check=true
EXIT_CODE=$?
echo $EXIT_CODE
# Some statements should be bad, code 2 must be returned:
if [ $EXIT_CODE -ne 2 ]; then
    exit 1
fi
set -e

# Start pgator server
./pgator --config=${1} --debug=true &
trap "kill %%" EXIT

ADDRESS=`jq '.listenAddresses[0]' ${1}`
ADDRESS_UNQUOTED=`echo $ADDRESS | xargs`
PORT=`jq '.listenPort' ${1}`

# Start test client
dub run pgator:test --build=unittest -- "$ADDRESS_UNQUOTED" "$PORT"
