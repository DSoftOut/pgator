// Written in D programming language
/**
*    Module describes simple testcases for rpc-server.
*    
*    Copyright: © 2014 DSoftOut
*    License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*    Authors: NCrashed <ncrashed@gmail.com>
*/
module client.test.simple;

import client.test.testcase;
import client.rpcapi;
import pgator.db.pool;

class SimpleTestCase : ITestCase
{
    protected void insertMethods(shared IConnectionPool pool, string tableName)
    {
        insertRow(pool, tableName, JsonRpcRow("plus1", 2, "SELECT $1::int8 + $2::int8 as test_field;"));
        insertRow(pool, tableName, JsonRpcRow("plus2", 2, "\"SELECT $1::int8 + $2::int8 as test_field1, $1::int8 - $2::int8 as test_field2;\""));
    }
    
    /**
    *   Removes row describing method from json_rpc table after tests are finished.
    */
    protected void deleteMethods(shared IConnectionPool pool, string tableName)
    {
        removeRow(pool, tableName, "plus1");
        removeRow(pool, tableName, "plus2");
    }
    
    /**
    *   All testing procedures should be located here. Rpc-server is called and respond
    *   is checked to be an expected value.
    */
    protected void performTests(IRpcApi api)
    {
        auto result1 = api.runRpc!"plus1"(2, 1).assertOk!(Column!(ulong, "test_field"));
        assert(result1.test_field[0] == 3);
        
        auto result2 = api.runRpc!"plus2"(2, 1).assertOk!(Column!(ulong, "test_field1"), Column!(ulong, "test_field2"));
        assert(result2.test_field1[0] == 3 && result2.test_field2[0] == 1);
    }
}