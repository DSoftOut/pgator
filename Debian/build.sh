#!/bin/bash

set -e

WORKDIR=/tmp/build
DEBDIR=${WORKDIR}/DEBIAN

mkdir -p ${DEBDIR}

VERSION=`git describe --match=v* | sed 's/^v//'`

echo "Package: pgator
Architecture: amd64
Version: $VERSION
Depends: libpq5 (>= 9.4~)
Maintainer: DSoftOut Crew
Description: Server that transforms JSON-RPC calls into SQL queries for PostgreSQL
" > ${DEBDIR}/control

cp Debian/conffiles ${DEBDIR}

mkdir -p ${WORKDIR}/etc/
mkdir -p ${WORKDIR}/usr/bin/

cp Debian/pgator.conf ${WORKDIR}/etc/
chmod 644 ${WORKDIR}/etc/pgator.conf # maybe it is need 600 ?

cp bin/pgator ${WORKDIR}/usr/bin/

dpkg -b ${WORKDIR} pgator_${VERSION}.deb

rm -rf ${WORKDIR}
