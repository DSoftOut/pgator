// Written in D programming language
/**
*    Module describes testcases for time consuming queries.
*    
*    Copyright: © 2014 DSoftOut
*    License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*    Authors: NCrashed <ncrashed@gmail.com>
*/
module client.test.longquery;

import client.test.testcase;
import client.rpcapi;
import db.pool;

class LongQueryTestCase : ITestCase
{
    protected void insertMethods(shared IConnectionPool pool, string tableName)
    {
        insertRow(pool, tableName, JsonRpcRow("long_query1", [1], "select pg_sleep( $1 );"));
    }
    
    /**
    *   Removes row describing method from json_rpc table after tests are finished.
    */
    protected void deleteMethods(shared IConnectionPool pool, string tableName)
    {
        removeRow(pool, tableName, "long_query1");
    }
    
    /**
    *   All testing procedures should be located here. Rpc-server is called and respond
    *   is checked to be an expected value.
    */
    protected void performTests(IRpcApi api)
    {
        auto result = api.runRpc!"long_query1"(10).assertOk!(Column!(string, "pg_sleep"));
        assert(result.pg_sleep[0] == "");
    }
}