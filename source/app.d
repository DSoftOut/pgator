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
    QueryParams p;
    p.sqlCommand = "SELECT * FROM "~client.escapeIdentifier(sqlPgatorTable);
    auto answer = client.execStatement(p, dur!"seconds"(10));

    struct Method
    {
        string[] args;
    }

    Method[string] methods;

    foreach(r; rangify(answer))
    {
        trace("found method row: ", r);

        string name = r["method"].as!string;

        Method m;

        {
            auto arr = r["args"].asArray;

            if(arr.nDims != 1)
                throw new Exception("array of args should be one dimensional", __FILE__, __LINE__);

            foreach(v; rangify(arr))
                m.args ~= v.as!string;
        }

        methods[name] = m;

        info("Method ", name, " added. Content: ", m);
    }

    // look for changes in the pgator_rpc

    // apply changes by preparing new statements

    return 0;
}
