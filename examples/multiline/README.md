Multiline transactions usage example
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
    auto bsonRange = pool.execTransaction(["select $1::numeric + $2::numeric as field1"
                                          ,"select $1::numeric - $2::numeric as field2"],
                                          ["10", "20",  // parameters for first query 
                                           "30", "40"], // parameters for second query
                                          [2, 2] // 2 params for first query, 2 params to second query
                                          );
    // Several responses are expected
    foreach(bson; bsonRange) writeln(bson);
```