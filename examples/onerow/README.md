One row constraint example
====================

Pool could force queries to return only one row in respond, if there are several rows - transaction is rollbacked and `OneRowConstraintException` is raised.

Build:
```
dub build
```

Run:
```
./pgator-backend-example-onerow --conn="Your postgresql connection string"
```

Important code
==============
``` D
    // Quering a server from pool
    auto bsonRange = pool.execTransaction(["select 10 as field"],
                                          [], // no parameters
                                          [], // no parameters
                                          null, // no vars
                                          [true] // indicates that first query should be one-row query
                                          );
    foreach(bson; bsonRange) writeln(bson);
    
    // Invalid query with rollback
    auto bsonRange2 = pool.execTransaction(["select 10 as field union select 11 as field"],
                                          [], // no parameters
                                          [], // no parameters
                                          null, // no vars
                                          [true] // indicates that first query should be one-row query
                                          );
    foreach(bson; bsonRange2) writeln(bson);
```