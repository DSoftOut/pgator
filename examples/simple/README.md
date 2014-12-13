Simple usage example
====================

Build:
```
dub build
```

Run:
```
./pgator-backend-example-simple --conn="Your postgresql connection string"
```

Important code
==============
``` D
    // Initializing concurrent logger
    auto logger = new shared StrictLogger(logName);
    scope(exit) logger.finalize();

    // Intitializing PostgreSQL bindings and Connection factory
    auto api = new shared PostgreSQL(logger);
    auto connProvider = new shared PQConnProvider(logger, api);

    // Creating pool
    auto pool = new shared AsyncPool(logger, connProvider
        , dur!"seconds"(1) // time between reconnection tries
        , dur!"seconds"(5) // maximum time to wait for free connection appearing in the pool while quering
        , dur!"seconds"(3) // every 3 seconds check connection
        );
    scope(failure) pool.finalize();

    // Adding server to the pool
    pool.addServer(connString, 1);

    // Quering a server from pool
    auto bsonRange = pool.execTransaction(["select 10 as test_field"]);
    // Almost there is one bson respond, but there could be more if you put several commands in a
    // transaction
    foreach(bson; bsonRange) writeln(bson);
```