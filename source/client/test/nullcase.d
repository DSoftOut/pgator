// Written in D programming language
/**
*    Module describes testcases about null values handling for rpc-server.
*    
*    Copyright: © 2014 DSoftOut
*    License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*    Authors: NCrashed <ncrashed@gmail.com>
*/
module client.test.nullcase;

import client.test.testcase;
import client.rpcapi;
import pgator.db.pool;
import std.conv;
import std.typecons;

import vibe.data.json;

class NullTestCase : ITestCase
{
    enum NullTest1 = "null1";
    enum NullTest2 = "null2";
    enum NullTest3 = "null3";
    enum NullTest4 = "null4";
    
    protected void insertMethods(shared IConnectionPool pool, string tableName)
    {
        insertRow(pool, tableName, JsonRpcRow(NullTest1, 2, "SELECT $1::integer + $2::integer as test_field;"));
        insertRow(pool, tableName, JsonRpcRow(NullTest2, "select NULL::text as null_test_value;"));
        insertRow(pool, tableName, JsonRpcRow(NullTest3, "select ''::text as null_test_value;"));
        insertRow(pool, tableName, JsonRpcRow(NullTest4, 1, "select $1::text as null_test_value;"));
    }
    
    /**
    *   Removes row describing method from json_rpc table after tests are finished.
    */
    protected void deleteMethods(shared IConnectionPool pool, string tableName)
    {
        removeRow(pool, tableName, NullTest1);
        removeRow(pool, tableName, NullTest2);
        removeRow(pool, tableName, NullTest3);
        removeRow(pool, tableName, NullTest4);
    }
    
    /**
    *   All testing procedures should be located here. Rpc-server is called and respond
    *   is checked to be an expected value.
    */
    protected void performTests(IRpcApi api)
    {
        auto result = api.runRpc!NullTest1(null, null).assertOk!(Column!(Nullable!ulong, "test_field"));
        assert(result.test_field.length == 1);
        assert(result.test_field[0].isNull);
        
        auto result2Raw = api.runRpc!NullTest2().raw;
        assert(result2Raw["result"]["null_test_value"][0].type == Json.Type.null_, text("Expected type 'null' but got '", result2Raw["result"]["null_test_value"][0].type, "'"));
        
        auto result3Raw = api.runRpc!NullTest3().raw;
        assert(result3Raw["result"]["null_test_value"][0].type == Json.Type.string, text("Expected type 'string' but got '", result2Raw["result"]["null_test_value"][0].type, "'"));
        
        auto result4 = api.runRpc!NullTest4("null").assertOk!(Column!(string, "null_test_value"));
        assert( result4.null_test_value[0] == "null");
    }
}