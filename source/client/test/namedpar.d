// Written in D programming language
/**
*    Module describes testcases for named parameters (issue #32)
*    
*    Copyright: © 2014 DSoftOut
*    License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*    Authors: NCrashed <ncrashed@gmail.com>
*/
module client.test.namedpar;

import client.test.testcase;
import client.rpcapi;
import db.pool;

class NamedParamsTestCase : ITestCase
{
    protected void insertMethods(shared IConnectionPool pool, string tableName)
    {
        insertRow(pool, tableName, JsonRpcRow("named_test1", [2], "SELECT $1::int8 + $2::int8 as test_field;"));
    }
    
    /**
    *   Removes row describing method from json_rpc table after tests are finished.
    */
    protected void deleteMethods(shared IConnectionPool pool, string tableName)
    {
        removeRow(pool, tableName, "named_test1");
    }
    
    /**
    *   All testing procedures should be located here. Rpc-server is called and respond
    *   is checked to be an expected value.
    */
    protected void performTests(IRpcApi api)
    {
        auto result = api.runRpc!"named_test1"(2, 1).assertOk!(Column!(ulong, "test_field"));
        assert(result.test_field[0] == 3);
    }
}
