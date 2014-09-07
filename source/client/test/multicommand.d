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
import db.pool;

class MulticommandCase : ITestCase
{
    protected void insertMethods(shared IConnectionPool pool, string tableName)
    {
        insertRow(pool, tableName, JsonRpcRow("multicommand_test1", [1, 1], ["SELECT $1::text as test_field1;", "SELECT $1::text as test_field2;"]));
    }
    
    /**
    *   Removes row describing method from json_rpc table after tests are finished.
    */
    protected void deleteMethods(shared IConnectionPool pool, string tableName)
    {
        removeRow(pool, tableName, "multicommand_test1");
    }
    
    /**
    *   All testing procedures should be located here. Rpc-server is called and respond
    *   is checked to be an expected value.
    */
    protected void performTests(IRpcApi api)
    {
        auto respond = api.runRpc!"multicommand_test1"("a", "b");
        
        auto result1 = respond.assertOk!(Column!(string, "test_field1"))(0);
        assert(result1.test_field1[0] == "a");
        
        auto result2 = respond.assertOk!(Column!(string, "test_field2"))(1);
        assert(result2.test_field2[0] == "b");
    }
}