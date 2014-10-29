#!/bin/bash
set -e

sed "s/TO_HOST/$DB_PORT_5432_TCP_ADDR/g" /etc/pgator.conf

/usr/bin/pgator
