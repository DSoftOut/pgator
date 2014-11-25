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
  "pgator-backend": ">=0.1.2"
}
```

Usage example (currently) can be found in the [testing code](https://github.com/DSoftOut/pgator-backend/blob/master/source/pgator/test/test2.d):
```D
    auto logger = new shared StrictLogger(logName);
    scope(exit) logger.finalize();
    
    auto api = new shared PostgreSQL(logger);
    auto connProvider = new shared PQConnProvider(logger, api);
    
    auto pool = new shared AsyncPool(logger, connProvider, dur!"seconds"(1), dur!"seconds"(5), dur!"seconds"(3));
    scope(failure) pool.finalize();
    
    pool.addServer(connString, 1);
    
    auto bsonRange = pool.execTransaction(["select 10 as test_field"]);
    foreach(bson; bsonRange) writeln(bson);
```
