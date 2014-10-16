// Written in D programming language
/**
*    Module describes testcases for error processing.
*    
*    Copyright: © 2014 DSoftOut
*    License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*    Authors: NCrashed <ncrashed@gmail.com>
*/
module client.test.notice;

import client.test.testcase;
import client.rpcapi;
import pgator.db.pool;

class NoticeTestCase : ITestCase
{
    protected void insertMethods(shared IConnectionPool pool, string tableName)
    {
        insertRow(pool, tableName, JsonRpcRow("notice_test1", [], [
            "DROP FUNCTION IF EXISTS pgator_testRaise();",
            
            "CREATE FUNCTION pgator_testRaise() RETURNS void AS $$"
            "BEGIN"
            "    RAISE NOTICE 'Test notice!';"
            "END;"
            "$$ LANGUAGE plpgsql;",
            
            "SELECT pgator_testRaise();",
            
            "DROP FUNCTION pgator_testRaise();"   
            ]));
    }
    
    /**
    *   Removes row describing method from json_rpc table after tests are finished.
    */
    protected void deleteMethods(shared IConnectionPool pool, string tableName)
    {
        removeRow(pool, tableName, "notice_test1");
    }
    
    /**
    *   All testing procedures should be located here. Rpc-server is called and respond
    *   is checked to be an expected value.
    */
    protected void performTests(IRpcApi api)
    {
        auto result = api.runRpc!"notice_test1"().assertOk;
    }
}