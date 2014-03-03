// Written in D programming language
/**
*    Module describes simple testcases for rpc-server.
*    
*    Authors: NCrashed <ncrashed@gmail.com>
*/
module client.test.simple;

import client.test.testcase;
import client.rpcapi;
import db.pool;

class SimpleTestCase : ITestCase
{
    protected void insertMethods(shared IConnectionPool pool, string tableName)
    {
        insertRow(pool, tableName, JsonRpcRow("plus", 2, "SELECT $1::int8 + $2::int8 as test_field;"));
    }
    
    /**
    *   Removes row describing method from json_rpc table after tests are finished.
    */
    protected void deleteMethods(shared IConnectionPool pool, string tableName)
    {
        removeRow(pool, tableName, "plus");
    }
    
    /**
    *   All testing procedures should be located here. Rpc-server is called and respond
    *   is checked to be an expected value.
    */
    protected void performTests(IRpcApi api)
    {
        auto result = api.runRpc!"plus"(2, 1).assertOk!(Column!(ulong, "test_field"));
        assert(result.test_field[0] == 3);
    }
}