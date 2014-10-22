// Written in D programming language
/**
*    Module describes simple testcases for rpc-server.
*    
*    Copyright: © 2014 DSoftOut
*    License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*    Authors: NCrashed <ncrashed@gmail.com>
*/
module client.test.numeric;

import client.test.testcase;
import client.rpcapi;
import pgator.db.pool;

class NumericTestCase : ITestCase
{
    protected void insertMethods(shared IConnectionPool pool, string tableName)
    {
        insertRow(pool, tableName, JsonRpcRow("numeric_test_1", 1, "SELECT $1::bigint test_field;"));
        insertRow(pool, tableName, JsonRpcRow("numeric_test_2", "select 2354877787627192443::bigint as bigint_value;"));
    }
    
    /**
    *   Removes row describing method from json_rpc table after tests are finished.
    */
    protected void deleteMethods(shared IConnectionPool pool, string tableName)
    {
        removeRow(pool, tableName, "numeric_test_1");
        removeRow(pool, tableName, "numeric_test_2");
    }
    
    /**
    *   All testing procedures should be located here. Rpc-server is called and respond
    *   is checked to be an expected value.
    */
    protected void performTests(IRpcApi api)
    {
        auto result1 = api.runRpc!"numeric_test_1"(2354877787627192443).assertOk!(Column!(long, "test_field"));
        assert(result1.test_field[0] == 2354877787627192443);
        
        auto result2 = api.runRpc!"numeric_test_2".assertOk!(Column!(long, "bigint_value"));
        assert(result2.bigint_value[0] == 2354877787627192443);
    }
}