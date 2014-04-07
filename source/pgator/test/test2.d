// Written in D programming language
/**
*   Integration test 2 performs major tests on real PostgreSQL instance. The configuration expects
*   '--conn' parameter with valid connection string to test database. There are many tests for
*   binary converting from libpq format. This test is the most important one as it should expose
*   libp binary format changing while updating to new versions. 
*
*   Copyright: © 2014 DSoftOut
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module pgator.test.test2;

version(IntegrationTest2):

import std.getopt;
import std.stdio;
import std.exception;
import dlogg.strict;
import pgator.db.pq.libpq;
import pgator.db.pq.connection;
import pgator.db.pq.types.conv;
import pgator.db.asyncPool;
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
    
    auto api = new shared PostgreSQL();
    logger.logInfo("PostgreSQL was inited.");
    auto connProvider = new shared PQConnProvider(logger, api);
    
    auto pool = new shared AsyncPool(logger, connProvider, dur!"seconds"(1), dur!"seconds"(5));
    scope(failure) pool.finalize();
    logger.logInfo("AssyncPool was created.");
    
    pool.addServer(connString, 1);
    logger.logInfo(text(1, " new connections were added to the pool."));
    
    logger.logInfo("Testing rollback...");
    assertThrown(pool.execTransaction(["select * from;"]));
    
    try
    {
        pool.execTransaction(["select 42::int8 as test_field;"]);
    } catch(QueryProcessingException e)
    {
        assert(false, "Transaction wasn't rollbacked! All queries after block are ignored!");
    }
    
    pool.addServer(connString, connCount-1);
    logger.logInfo(text(connCount-1, " new connections were added to the pool."));
    logger.logInfo("Testing binary protocol...");
    try
    {
        testConvertions(logger, pool);
    } catch(Throwable e)
    {
        logger.logInfo("Conversion tests are failed!");
        logger.logError(text(e));
    }
    
    pool.finalize();
    logger.finalize();
    std.c.stdlib.exit(0);
    return 0;
}