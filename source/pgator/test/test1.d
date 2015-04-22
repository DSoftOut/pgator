// Written in D programming language
/**
*   Integration test 1 performs simple tests on real PostgreSQL instance. The configuration expects
*   '--conn' parameter with valid connection string to test database. The main thing that is tested
*   is connection pool operational correctness.
*
*   Copyright: © 2014 DSoftOut
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*            Zaramzan <shamyan.roman@gmail.com>
*/
module pgator.test.test1; 

version(IntegrationTest1):

import std.getopt;
import std.stdio;
import std.range;
import dlogg.strict;
import pgator.db.pq.libpq;
import pgator.db.pq.connection;
import pgator.db.async.pool;    
import core.time;
import core.thread;

int main(string[] args)
{
    string connString;
    string logName = "test.log";
    uint connCount = 50;
    getopt(args
        , "conn",  &connString
        , "log",   &logName
        , "count", &connCount);
    
    if(connString == "")
    {
        writeln("Please, specify connection string.\n"
                "Params: --conn=string - connection string to test PostgreSQL connection\n"
                "        --log=string  - you can rewrite log file location, default 'test.log'\n"
                "        --count=uint  - number of connections in a pool, default 100\n");
        return 0;
    }
    
    auto logger = new shared StrictLogger(logName);
    scope(exit) logger.finalize();
    
    auto api = new shared PostgreSQL(logger);
    logger.logInfo("PostgreSQL was inited.");
    auto connProvider = new shared PQConnProvider(logger, api);
    
    auto pool = new shared AsyncPool(logger, connProvider, dur!"seconds"(5), dur!"seconds"(5), dur!"seconds"(3));
    scope(exit) pool.finalize();
    logger.logInfo("AssyncPool was created.");
    
    pool.addServer(connString, connCount);
    logger.logInfo(text(connCount, " new connections were added to the pool."));
    
    Thread.sleep(dur!"seconds"(30));
    
    logger.logInfo("Test ended. Results:"); 
    logger.logInfo(text("active connections:   ", pool.activeConnections));
    logger.logInfo(text("inactive connections: ", pool.inactiveConnections));
    
    pool.finalize();
    logger.finalize();
    core.stdc.stdlib.exit(0);
    return 0;
}
