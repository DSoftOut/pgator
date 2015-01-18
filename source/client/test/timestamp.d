// Written in D programming language
/**
*    Module describes testcases about timestamp conversions.
*    
*    Copyright: © 2014 DSoftOut
*    License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*    Authors: NCrashed <ncrashed@gmail.com>
*/
module client.test.timestamp;

import client.test.testcase;
import client.rpcapi;
import pgator.db.pool;
import std.conv;
import std.typecons;
import std.datetime;

import vibe.data.json;

class TimestampCase : ITestCase
{
    enum Test1 = "timestamp1";
    
    protected void insertMethods(shared IConnectionPool pool, string tableName)
    {
        insertRow(pool, tableName, JsonRpcRow(Test1, 0, "select '2014-11-20 15:47:25.58+07'::timestamp with time zone as test_field"));
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
        auto result = api.runRpc!Test1().assertOk!(Column!(string, "test_field"));
        assert(result.test_field.length == 1);
        assert(SysTime.fromISOExtString(result.test_field[0]) == SysTime.fromSimpleString("2014-Nov-20 15:47:25.58+07"), 
        	text(result.test_field[0], " != 2014-11-20 15:47:25.58+07"));
    }
}