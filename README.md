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

Usage examples:
- [Simple example](https://github.com/DSoftOut/pgator-backend/tree/master/examples/simple)
- [Multiline transactions](https://github.com/DSoftOut/pgator-backend/tree/master/examples/multiline)
- [Server configurations](https://github.com/DSoftOut/pgator-backend/tree/master/examples/locals)
- [One row constraints](https://github.com/DSoftOut/pgator-backend/tree/master/examples/onerow)
