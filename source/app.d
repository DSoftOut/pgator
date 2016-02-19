import std.getopt;
import std.experimental.logger;

shared static this()
{
    sharedLog.fatalHandler = null;
}

string configFileName = "/wrong/path/to/file.json";
bool debugEnabled = false;

void readOpts(string[] args)
{
    try
    {
        auto helpInformation = getopt(
                args,
                "debug", &debugEnabled,
                "config", &configFileName
            );
    }
    catch(Exception e)
    {
        fatal(e.msg);
    }

    if(!debugEnabled) sharedLog.logLevel = LogLevel.warning;
}

import vibe.data.json;
import vibe.data.bson;

private Bson _cfg;

Bson readConfig()
{
    import std.file;

    Bson cfg;

    try
    {
        auto text = readText(configFileName);
        cfg = Bson(parseJsonString(text));
    }
    catch(Exception e)
    {
        fatal(e.msg);
        throw e;
    }

    return cfg;
}

int main(string[] args)
{
    readOpts(args);
    Bson cfg = readConfig();

    import vibe.db.postgresql;

    auto server = cfg["sqlServer"];
    auto connString = server["connString"].get!string;
    auto maxConn = to!uint(server["maxConn"].get!long);

    // connect to db
    auto client = connectPostgresDB(connString, maxConn, true);
    auto sqlPgatorTable = cfg["sqlPgatorTable"].get!string;

    // read pgator_rpc
    immutable tableName = client.escapeIdentifier(sqlPgatorTable);
    QueryParams p;
    p.sqlCommand = "SELECT * FROM "~tableName;
    auto answer = client.execStatement(p, dur!"seconds"(10));

    struct Method
    {
        string name;
        string statement;
        string[] args;
        bool oneRowFlag;
    }

    Method[string] methods;

    foreach(r; rangify(answer))
    {
        trace("found method row: ", r);

        void getOptional(T)(string sqlName, ref T result)
        {
            try
            {
                auto v = r[sqlName];

                if(v.isNull)
                    throw new Exception("Value of column "~sqlName~" is NULL", __FILE__, __LINE__);

                result = v.as!T;
            }
            catch(AnswerException e)
            {
                if(e.type != ExceptionType.COLUMN_NOT_FOUND) throw e;
            }
        }

        Method m;

        try
        {
            m.name = r["method"].as!string;

            if(m.name.length == 0)
                throw new Exception("Method name is empty string", __FILE__, __LINE__);

            m.statement = r["sql_query"].as!string;

            {
                auto arr = r["args"].asArray;

                if(arr.dimsSize.length > 1)
                    throw new Exception("Array of args should be one dimensional", __FILE__, __LINE__);

                foreach(v; rangify(arr))
                    m.args ~= v.as!string;
            }

            getOptional("one_row_flag", m.oneRowFlag);
        }
        catch(Exception e)
        {
            warning(e.msg, ", skipping reading of method ", m.name);
            continue;
        }

        methods[m.name] = m;
        info("Method ", m.name, " loaded. Content: ", m);
    }

    size_t failedCount = answer.length - methods.length;
    trace("Number of methods in the table ", tableName,": ", answer.length, ", failed to load: ", failedCount);

    {
        // try to prepare methods
        size_t counter = methods.length;

        foreach(m; methods)
        {
            trace("try to prepare method ", m.name);

            try
            {
                auto r = client.prepareStatement(m.name, m.statement, m.args.length, dur!"seconds"(5));

                if(r.status != PGRES_COMMAND_OK)
                    throw new Exception(r.resultErrorMessage, __FILE__, __LINE__);
            }
            catch(Exception e)
            {
                warning(e.msg, ", skipping preparing of method ", m.name);
                failedCount++;
                continue;
            }
        }

        info("Number of methods in the table ", tableName,": ", answer.length, ", failed to prepare: ", failedCount);
    }

    {
        // try to use prepared statement
        QueryParams qp;
        qp.preparedStatementName = "echo";
        qp.args.length = 1;
        qp.args[0].value = "test value";
        auto r = client.execPreparedStatement(qp);

        import std.stdio;
        writeln(r);
    }

    return 0;
}
