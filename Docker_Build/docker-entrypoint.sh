#!/bin/bash
/bin/sh set -e

sed -i s/TO_HOST/$DB_PORT_5432_TCP_ADDR/g /etc/pgator.conf
sed -i s/TO_PORT/$DB_PORT_5432_TCP_PORT/g /etc/pgator.conf

psql --username=postgres --host=$DB_PORT_5432_TCP_ADDR --port=$DB_PORT_5432_TCP_PORT -d postgres -f migrate-db.sql

cd /var/local/pgator 
dub upgrade
dub test
dub build --config=production --build=release
dub build --config=production --build=debug
dub build --config=testclient --build=debug

./bin/pgator --config="/etc/pgator.conf" &
./bin/pgator-client --conn="host=$DB_PORT_5432_TCP_ADDR port=$DB_PORT_5432_TCP_PORT dbname=postgres user=postgres" --host="http://127.0.0.1:8080/"

kill -s SIGTERM $(pgrep pgator)
cat ./pgator.log