// Written in D programming language
/**
*    Module describes testcases about handling one row queries. Related to issue #51.
*    
*    Copyright: © 2014 DSoftOut
*    License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*    Authors: NCrashed <ncrashed@gmail.com>
*/
module client.test.onerow;

import client.test.testcase;
import client.rpcapi;
import pgator.db.pool;
import std.conv;
import std.typecons;

import vibe.data.json;

class OneRowTestCase : ITestCase
{
    enum Test1 = "onerow1";
    enum Test2 = "onerow2";
    enum Test3 = "onerow3";
    enum Test4 = "onerow4";
    
    protected void insertMethods(shared IConnectionPool pool, string tableName)
    {
        insertRow(pool, tableName, JsonRpcRow(Test1, [0], ["SELECT 10::integer as field;"]
                , false, false, false,
                [], [], [], [true]));
        
        insertRow(pool, tableName, JsonRpcRow(Test2, [0], ["SELECT 10::integer as field union all select 11::integer as field;"]
                , false, false, false,
                [], [], [], [true]));
        
        insertRow(pool, tableName, JsonRpcRow(Test3, [0, 0], ["SELECT 10::integer as field;", "SELECT 10::integer as field union all select 11::integer as field;"]
                , false, false, false,
                [], [], [], [true, false]));
        
        insertRow(pool, tableName, JsonRpcRow(Test4, [0, 0], ["SELECT 10::integer as field union all select 11::integer as field;", "SELECT 10::integer as field;"]
                , false, false, false,
                [], [], [], [false, true]));
    }
    
    /**
    *   Removes row describing method from json_rpc table after tests are finished.
    */
    protected void deleteMethods(shared IConnectionPool pool, string tableName)
    {
        removeRow(pool, tableName, Test1);
        removeRow(pool, tableName, Test2);
        removeRow(pool, tableName, Test3);
        removeRow(pool, tableName, Test4);
    }
    
    /**
    *   All testing procedures should be located here. Rpc-server is called and respond
    *   is checked to be an expected value.
    */
    protected void performTests(IRpcApi api)
    {
        {
            auto result = api.runRpc!Test1.assertOk!(Column!(ulong, "field"));
            assert(result.field.length == 1);
            assert(result.field[0] == 10);
        }
        {
           auto result = api.runRpc!Test2.assertError;
           assert(result.code == -32000);
        }
        {
            auto result1 = api.runRpc!Test3.assertOk!(Column!(ulong, "field"))(0);
            assert(result1.field.length == 1);
            assert(result1.field[0] == 10);
            
            auto result2 = api.runRpc!Test3.assertOk!(Column!(ulong, "field"))(1);
            assert(result2.field.length == 2);
            assert(result2.field[0] == 10);
            assert(result2.field[1] == 11);
        }
        {
            auto result1 = api.runRpc!Test4.assertOk!(Column!(ulong, "field"))(1);
            assert(result1.field.length == 1);
            assert(result1.field[0] == 10);
            
            auto result2 = api.runRpc!Test4.assertOk!(Column!(ulong, "field"))(0);
            assert(result2.field.length == 2);
            assert(result2.field[0] == 10);
            assert(result2.field[1] == 11);
        }
    }
}