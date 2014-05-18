// Written in D programming language
/**
*   This module defines a test case for rpc-server.
*
*   Test case includes json_rpc table row description,
*   test params and expected response.
*
*   Copyright: © 2014 DSoftOut
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module client.test.testcase;

import client.rpcapi;
import db.pool;
import std.conv;
import std.typecons;
import std.array;
import std.process;

interface ITestCase
{
    /**
    *   Wrapper method to ensure testing table is freed after the test.
    */
    final void run(IRpcApi api, shared IConnectionPool pool, string tableName, uint serverPid)
    {
        insertMethods(pool, tableName);
        scope(exit) deleteMethods(pool, tableName);
        
        updateServerTables(serverPid);
        performTests(api);
    }
    
    /**
    *   Inserts a row in json_rpc table before testing process.
    */
    protected void insertMethods(shared IConnectionPool pool, string tableName);
    
    /**
    *   Removes row describing method from json_rpc table after tests are finished.
    */
    protected void deleteMethods(shared IConnectionPool pool, string tableName);
    
    /**
    *   All testing procedures should be located here. Rpc-server is called and respond
    *   is checked to be an expected value.
    */
    protected void performTests(IRpcApi api);
    
    protected final void insertRow(shared IConnectionPool pool, string tableName, JsonRpcRow row)
    {
        pool.execTransaction(["INSERT INTO \""~tableName~"\" VALUES ($1, $2, $3, $4, $5, $6, $7, $8);"],
            [row.method, 
            row.sql_queries.convertArray, 
            row.arg_nums.convertArray,
            row.set_username.to!string,
            row.need_cache.to!string,
            row.read_only.to!string,
            row.reset_caches.convertArray,
            row.reset_by.convertArray],
            [8]);
    }
    
    protected final void removeRow(shared IConnectionPool pool, string tableName, string method)
    {
        pool.execTransaction(["DELETE FROM \""~tableName~"\" WHERE method = $1;"], [method], [1]);
    }
}

private void updateServerTables(uint pid)
{
    executeShell(text("kill -s HUP ", pid));
}

private string convertArray(T)(T[] ts)
{
    auto builder = appender!string;
    foreach(i,t; ts)
    {
        //static if(is(T == string)) builder.put("'");
        static if(is(T == float))
        {
           if(t == T.infinity) builder.put("'Infinity'");
           else if(t == -T.infinity) builder.put("'-Infinity'");
           else if(isnan(t)) builder.put("'NaN'");
           else builder.put(t.to!string);
        } else
        {
            builder.put(t.to!string);
        }
       // static if(is(T == string)) builder.put("'");
        if(i != ts.length-1)
            builder.put(", ");
    }
    return "{"~builder.data~"}";
} 
    
/**
*   Struct that represents one row in json_rpc table.   
*/
struct JsonRpcRow
{
    string method;
    string[] sql_queries;
    uint[] arg_nums;
    bool set_username;
    bool need_cache;
    bool read_only;
    string[] reset_caches;
    string[] reset_by;
    
    this(string method, uint[] arg_nums, string sql_query)
    {
        this.method = method;
        this.arg_nums = arg_nums;
        this.sql_queries = [sql_query];
    } 
    
    this(string method, uint[] arg_nums, string[] sql_queries,
        bool set_username = false, bool need_cache = true,
        bool read_only = true, string[] reset_caches = [],
        string[] reset_by = [])
    {
        this.method = method;
        this.sql_queries = sql_queries;
        this.arg_nums = arg_nums;
        this.set_username = set_username;
        this.read_only = read_only;
        this.need_cache = need_cache;
        this.reset_caches = reset_caches;
        this.reset_by = reset_by;
    }
}