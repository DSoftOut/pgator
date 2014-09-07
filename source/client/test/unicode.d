// Written in D programming language
/**
*    Module describes testcases for UTF-8 encoding.
*    
*    Copyright: © 2014 DSoftOut
*    License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*    Authors: NCrashed <ncrashed@gmail.com>
*/
module client.test.unicode;

import client.test.testcase;
import client.rpcapi;
import db.pool;

class UnicodeTestCase : ITestCase
{
    protected void insertMethods(shared IConnectionPool pool, string tableName)
    {
        insertRow(pool, tableName, JsonRpcRow("unicode_test1", [1], "SELECT $1::text as test_field;"));
    }
    
    /**
    *   Removes row describing method from json_rpc table after tests are finished.
    */
    protected void deleteMethods(shared IConnectionPool pool, string tableName)
    {
        removeRow(pool, tableName, "unicode_test1");
    }
    
    /**
    *   All testing procedures should be located here. Rpc-server is called and respond
    *   is checked to be an expected value.
    */
    protected void performTests(IRpcApi api)
    {
        auto result = api.runRpc!"unicode_test1"("Кусок юникод текста").assertOk!(Column!(string, "test_field"));
        assert(result.test_field[0] == "Кусок юникод текста");
    }
}