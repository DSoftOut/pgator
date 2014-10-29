#!/bin/bash
set -e

sed -i "s/TO_HOST/$DB_PORT_5432_TCP_ADDR/g" /etc/pgator.conf
sed -i "s/TO_PORT/$DB_PORT_5432_TCP_PORT/g" /etc/pgator.conf

exec /usr/bin/pgator
