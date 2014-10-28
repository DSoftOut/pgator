#!/bin/bash

set -e

WORKDIR=/tmp/build

mkdir -p ${WORKDIR}

cp -r Debian/DEBIAN ${WORKDIR}/
cp -r Debian/etc ${WORKDIR}/

VERSION=`git describe --match=v* | sed 's/^v//'`

echo "Package: pgator
Architecture: amd64
Version: $VERSION
Depends: libpq5 (>= 9.4~), supervisor (>=3.0~)
Maintainer: DSoftOut Crew
Description: Server that transforms JSON-RPC calls into SQL queries for PostgreSQL
" > ${WORKDIR}/DEBIAN/control

mkdir -p ${WORKDIR}/usr/bin/

cp bin/pgator ${WORKDIR}/usr/bin/

fakeroot dpkg-deb --build ${WORKDIR} pgator_${VERSION}.deb

rm -rf ${WORKDIR}
