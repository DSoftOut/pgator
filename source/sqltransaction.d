module pgator.sqltransaction;

import vibe.db.postgresql;

class SQLTransaction
{
    private Connection conn;
    private bool isCommitDone = false;

    this(PostgresClient client, bool isReadOnly)
    {
        conn = client.lockConnection();

        execPrepared(isReadOnly ? BuiltInPrep.BEGIN_RO : BuiltInPrep.BEGIN);
    }

    void commit()
    {
        execPrepared(BuiltInPrep.COMMIT);
        isCommitDone = true;
    }

    ~this()
    {
        if(!isCommitDone)
            execPrepared(BuiltInPrep.ROLLBACK);
    }

    private void execPrepared(BuiltInPrep prepared)
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
