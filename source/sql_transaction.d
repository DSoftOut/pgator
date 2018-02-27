module pgator.sql_transaction;

import pgator.rpc_table;
import pgator.app;
import vibe.db.postgresql;

struct TransactionQueryParams
{
    QueryParams[] queryParams;
    AuthorizationCredentials auth;
}

struct SQLTransaction
{
    private LockedConnection conn;
    private bool opened = false;

    @disable this(this){}

    this(PostgresClient client)
    {
        conn = client.lockConnection();
    }

    void begin(bool isReadOnly)
    {
        execBuiltIn(isReadOnly ? BuiltInPrep.BEGIN_RO : BuiltInPrep.BEGIN);
        opened = true;
    }

    void resetStart()
    {
        import vibe.core.log;

        logDebugV(__FUNCTION__);

        opened = false;
        conn.resetStart();
    }

    void commit()
    {
        execBuiltIn(BuiltInPrep.COMMIT);
        opened = false;
    }

    ~this()
    {
        if(opened)
            execBuiltIn(BuiltInPrep.ROLLBACK);

        destroy(conn);
    }

    immutable(Answer)[] execMethod(in Method method, TransactionQueryParams qp)
    {
        assert(opened);

        if(method.needAuthVariablesFlag)
        {
            QueryParams q;
            q.preparedStatementName = BuiltInPrep.SET_AUTH_VARS;
            q.args = [qp.auth.username.toValue, qp.auth.password.toValue];

            conn.execPreparedStatement(q);
        }

        immutable(Answer)[] ret;

        foreach(i, s; method.statements)
        {
            ret ~= conn.execPreparedStatement(qp.queryParams[i]);
        }

        return ret;
    }

    private void execBuiltIn(BuiltInPrep prepared)
    {
        QueryParams q;
        q.preparedStatementName = prepared;

        conn.execPreparedStatement(q);
    }
}

enum BuiltInPrep : string
{
    BEGIN = "#b#",
    BEGIN_RO = "#r#",
    COMMIT = "#C#",
    ROLLBACK = "#R#",
    SET_AUTH_VARS = "#a#"
}
