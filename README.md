[![Build Status](https://travis-ci.org/DSoftOut/pgator-backend.svg?branch=master)](https://travis-ci.org/DSoftOut/pgator-backend)

pgator-backend
==============

This package is part of [pgator](https://github.com/DSoftOut/pgator) json rpc server that could be used as dedicated libary.

Features:
* Lightweight bindings for PostgreSQL
* Asynchronous connection pool
* Reversed libpq binary protocol for BSON conversion

Supported types
===============
The bson converter can handle following types received from PostgreSQL:
* POD types (Char, Bool, Int8, Int4, Int2, Float8, Float4, Void, Money)
* ByteArrays
* Strings (Text, FixedString, VariableString)
* Oid, Tid, Xid, Cid
* Json, Xml (returned as a string)
* RegProc
* Point, Path, Polygone, LineSegment, Circle
* MacAddress, InetAddress
* Numeric
* Date, AbsTime, RelTime, Time, TimeWithZone, TimeInterval, Interval, TimeStamp, TimeStampWithZone
* Arrays and Array of ByteArray

Usage
======
Add to dub.json file:
```Json
"dependencies": {
  "pgator-backend": ">=0.1.2"
}
```

Usage example can be found in the [testing code](https://github.com/DSoftOut/pgator-backend/blob/master/source/pgator/test/test2.d):
```D
    // Initializing concurrent logger
    auto logger = new shared StrictLogger(logName);
    scope(exit) logger.finalize();
    
    // Intitializing PostgreSQL bindings and Connection factory
    auto api = new shared PostgreSQL(logger);
    auto connProvider = new shared PQConnProvider(logger, api);
    
    // Creating pool
    auto pool = new shared AsyncPool(logger, connProvider, dur!"seconds"(1), dur!"seconds"(5), dur!"seconds"(3));
    scope(failure) pool.finalize();
    
    // Adding server to the pool
    pool.addServer(connString, 1);
    
    // Quering a server from pool
    auto bsonRange = pool.execTransaction(["select 10 as test_field"]);
    // Almost there is one bson respond, but there could be more if you put several commands in a
    // transaction
    foreach(bson; bsonRange) writeln(bson);
```
