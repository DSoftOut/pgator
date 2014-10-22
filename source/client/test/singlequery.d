// Written in D programming language
/**
*    Module describes testcases about handling one table response special case for rpc-server.
*    
*    Copyright: © 2014 DSoftOut
*    License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*    Authors: NCrashed <ncrashed@gmail.com>
*/
module client.test.singlequery;

import client.test.testcase;
import client.rpcapi;
import pgator.db.pool;
import std.conv;
import std.typecons;

import vibe.data.json;

class SingleQueryTestCase : ITestCase
{
    enum Test1 = "null1";
    
    protected void insertMethods(shared IConnectionPool pool, string tableName)
    {
        insertRow(pool, tableName, JsonRpcRow(Test1, [2], "SELECT $1::integer + $2::integer as test_field;"));
    }
    
    /**
    *   Removes row describing method from json_rpc table after tests are finished.
    */
    protected void deleteMethods(shared IConnectionPool pool, string tableName)
    {
        removeRow(pool, tableName, Test1);
    }
    
    /**
    *   All testing procedures should be located here. Rpc-server is called and respond
    *   is checked to be an expected value.
    */
    protected void performTests(IRpcApi api)
    {
        auto result = api.runRpc!Test1(1, 2).assertOk!(Column!(int, "test_field"));
        assert(result.test_field.length == 1);
        assert(result.test_field[0] == 3);
    }
}