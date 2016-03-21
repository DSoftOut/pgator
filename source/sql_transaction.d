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
    private Connection conn;
    private bool isCommitDone = false;

    @disable this(this){}

    this(shared PostgresClient client, bool isReadOnly)
    {
        conn = client.lockConnection();

        execBuiltIn(isReadOnly ? BuiltInPrep.BEGIN_RO : BuiltInPrep.BEGIN);
    }

    void commit()
    {
        execBuiltIn(BuiltInPrep.COMMIT);
        isCommitDone = true;
    }

    ~this()
    {
        if(!isCommitDone) // TODO: also need check connection status
            execBuiltIn(BuiltInPrep.ROLLBACK);
    }

    immutable(Answer)[] execMethod(in Method method, TransactionQueryParams qp)
    {
        assert(!isCommitDone);

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
