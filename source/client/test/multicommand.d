// Written in D programming language
/**
*    Module describes testcases multiple command transaction. 
*    
*    Copyright: © 2014 DSoftOut
*    License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*    Authors: NCrashed <ncrashed@gmail.com>
*/
module client.test.multicommand;

import client.test.testcase;
import client.rpcapi;
import pgator.db.pool;

class MulticommandCase : ITestCase
{
    enum Test1 = "multicommand_test1";
    enum Test2 = "multicommand_test2";
    enum Test3 = "multicommand_test3";
    
    protected void insertMethods(shared IConnectionPool pool, string tableName)
    {
        insertRow(pool, tableName, JsonRpcRow(Test1, [1, 1], ["SELECT $1::text as test_field1;", "SELECT $1::text as test_field2;"]));
        insertRow(pool, tableName, JsonRpcRow(Test2, [0, 0], ["select 123 as col1", "select 456 as col2"]));
        insertRow(pool, tableName, JsonRpcRow(Test3, [0, 0], ["select 1 as c1", "2 as c2"]));
    }
    
    /**
    *   Removes row describing method from json_rpc table after tests are finished.
    */
    protected void deleteMethods(shared IConnectionPool pool, string tableName)
    {
        removeRow(pool, tableName, Test1);
        removeRow(pool, tableName, Test2);
        removeRow(pool, tableName, Test3);
    }
    
    /**
    *   All testing procedures should be located here. Rpc-server is called and respond
    *   is checked to be an expected value.
    */
    protected void performTests(IRpcApi api)
    {
        {
            auto respond = api.runRpc!Test1("a", "b");
            
            auto result1 = respond.assertOk!(Column!(string, "test_field1"))(0);
            assert(result1.test_field1[0] == "a");
            
            auto result2 = respond.assertOk!(Column!(string, "test_field2"))(1);
            assert(result2.test_field2[0] == "b");
        }
        {
            auto respond = api.runRpc!Test2();
            
            auto result1 = respond.assertOk!(Column!(int, "col1"))(0);
            assert(result1.col1[0] == 123);
            
            auto result2 = respond.assertOk!(Column!(int, "col2"))(1);
            assert(result2.col2[0] == 456);
        }
        {
            auto respond = api.runRpc!Test3().assertError();
        }
    }
}