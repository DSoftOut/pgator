module client.test.auth_info;

import client.test.testcase;
import client.rpcapi;
import pgator.db.pool;

class AuthInfoTestCase : ITestCase
{
    protected void insertMethods(shared IConnectionPool pool, string tableName)
    {
        insertRow(pool, tableName,
            JsonRpcRow("with_auth", [0],
                ["SELECT current_setting('pgator.username') as username, current_setting('pgator.password') as pass"],
                true
            )
        );
        //insertRow(pool, tableName, JsonRpcRow("without_auth", 0, "SELECT $1::int8 + $2::int8 as test_field;"));
    }
    
    /**
    *   Removes row describing method from json_rpc table after tests are finished.
    */
    protected void deleteMethods(shared IConnectionPool pool, string tableName)
    {
        removeRow(pool, tableName, "with_auth");
        //removeRow(pool, tableName, "without_auth");
    }
    
    /**
    *   All testing procedures should be located here. Rpc-server is called and respond
    *   is checked to be an expected value.
    */
    protected void performTests(IRpcApi api)
    {
        auto with_auth = api.runRpc!"with_auth"(2, 1).assertOk!(Column!(string, "username"), Column!(string, "pass"));
        assert(with_auth.username[0] == "Aladdin");
        assert(with_auth.pass[0] == "open sesame");
        
        //auto result2 = api.runRpc!"without_auth"(2, 1).assertOk!(Column!(ulong, "test_field1"), Column!(ulong, "test_field2"));
        //assert(result2.test_field1[0] == 3 && result2.test_field2[0] == 1);
    }
}
