// Written in D programming language
/**
*   This module defines rpc client class for testing rpc server.
*
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module client.client;

import std.stdio;
import core.time;
import vibe.data.json;
import vibe.http.rest;
import client.rpcapi;
import client.test.testcase;
import db.pool;
import db.asyncPool;
import db.pq.libpq;
import db.pq.connection;
import log;
import stdlog;

class RpcClient(T...)
{
    this(string host, string connString, string jsonRpcTable, uint serverPid)
    {
        this.jsonRpcTable = jsonRpcTable;
        this.serverPid = serverPid;
        api = new RestInterfaceClient!IRpcApi(host);
        
        logger = new shared CLogger("rpc-client.log");
        
        auto postgresApi = new PostgreSQL();
        auto connProvider = new shared PQConnProvider(logger, postgresApi);
        
        pool = new shared AsyncPool(logger, connProvider, dur!"seconds"(1), dur!"seconds"(5));
        
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