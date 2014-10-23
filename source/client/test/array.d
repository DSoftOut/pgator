// Written in D programming language
/**
*    Module describes testcases about handling array types for rpc-server.
*    
*    Copyright: © 2014 DSoftOut
*    License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*    Authors: NCrashed <ncrashed@gmail.com>
*/
module client.test.array;

import client.test.testcase;
import client.rpcapi;
import pgator.db.pool;
import std.conv;
import std.typecons;

import vibe.data.json;

class ArrayTestCase : ITestCase
{
    enum Test1 = "array1";
    
    protected void insertMethods(shared IConnectionPool pool, string tableName)
    {
        insertRow(pool, tableName, JsonRpcRow(Test1, 
                "\"select array[1,2,3]::integer[] as i, array[1,2,3]::numeric[] as n;\""
                ));
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
        {
            auto result = api.runRpc!Test1.assertOk!(Column!(int[], "i"), Column!(int[], "n"));
            assert(result.i.length == 1);
            assert(result.n.length == 1);
            assert(result.i[0] == [1, 2, 3]);
            assert(result.n[0] == [1, 2, 3]);
        }
    }
}