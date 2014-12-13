Server configuration setting example
====================

Build:
```
dub build
```

Run:
```
./pgator-backend-example-multiline --conn="Your postgresql connection string"
```

Important code
==============
``` D
    // Quering a server from pool
    auto bsonRange = pool.execTransaction(["SHOW enable_mergejoin"],
                                          [], // no parameters
                                          [], // no parameters
                                          ["enable_mergejoin": "true"] // setting server configuration value
                                          );
    foreach(bson; bsonRange) writeln(bson);
```