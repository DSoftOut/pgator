[![Build Status](https://travis-ci.org/DSoftOut/pgator-backend.svg?branch=master)](https://travis-ci.org/DSoftOut/pgator-backend)

pgator-backend
==============

This package is part of [pgator](https://github.com/DSoftOut/pgator) json rpc server that could be used as dedicated libary.

Features:
* Lightweight bindings for PostgreSQL
* Asynchronous connection pool
* Reversed libpq binary protocol for BSON conversion

Usage
======
Add to dub.json file:
```Json
"dependencies": {
  "pgator-backend": ">=0.1.0"
}
```
