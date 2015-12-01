// Written in D programming language
/**
*   This module defines rpc client class for testing rpc server.
*
*   Copyright: © 2014 DSoftOut
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module client.client;

import std.stdio;
import core.time;
import vibe.data.json;
import vibe.web.rest;
import client.rpcapi;
import client.test.testcase;
import pgator.db.pool;
import pgator.db.async.pool;    
import pgator.db.pq.libpq;
import pgator.db.pq.connection;
import dlogg.strict;

class RpcClient(T...)
{
    this(string host, string connString, string jsonRpcTable, uint serverPid)
    {
        this.jsonRpcTable = jsonRpcTable;
        this.serverPid = serverPid;
        api = new RestInterfaceClient!IRpcApi(host);
        
        logger = new shared StrictLogger("rpc-client.log");
        
        auto postgresApi = new shared PostgreSQL(logger);
        auto connProvider = new shared PQConnProvider(logger, postgresApi);
        
        pool = new shared AsyncPool(logger, connProvider, dur!"seconds"(1), dur!"seconds"(5), dur!"seconds"(3));
        
        pool.addServer(connString, 2);
    }
    
    void finalize()
    {
        pool.finalize();
        logger.finalize();
    }
    
    void runTests()
    {
        foreach(TestCase; T)
        {
            static assert(is(TestCase : ITestCase));
            auto test = new TestCase();
            test.run(api, pool, jsonRpcTable, serverPid);
        }
    }
    
    private 
    {
        RestInterfaceClient!IRpcApi api;
        shared IConnectionPool pool;
        shared ILogger logger;
        string jsonRpcTable;
        uint serverPid;
    } 
}
