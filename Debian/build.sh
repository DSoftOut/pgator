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

mkdir -p ${WORKDIR}/usr/bin/
cp -a bin/pgator ${WORKDIR}/usr/bin/

dpkg -b ${WORKDIR} pgator_${VERSION}.deb

rm -rf ${DEBDIR}
