import std.getopt;
import std.experimental.logger;
import vibe.http.server;

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

    foreach(ref r; rangify(answer))
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

                foreach(ref v; rangify(arr))
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

        foreach(const m; methods.byValue)
        {
            trace("try to prepare method ", m.name);

            try
            {
                client.prepareStatement(m.name, m.statement, m.args.length, dur!"seconds"(5));
            }
            catch(ConnectionException e)
            {
                throw e;
            }
            catch(Exception e)
            {
                warning(e.msg, ", skipping preparing of method ", m.name);
                failedCount++;
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

        assert(r[0][0].as!string == qp.args[0].value);
    }

    {
        // http-server
        import vibe.http.router;
        import vibe.core.core;

        void httpRequestHandler(scope HTTPServerRequest req, HTTPServerResponse res)
        {
            auto rr = RpcRequest.toRpcRequest(req);

            res.writeJsonBody("it works!"~
                "named params: "~rr.namedParams.to!string~
                "positional params: "~rr.positionParams.to!string);
        }

        auto settings = new HTTPServerSettings;
        settings.options |= HTTPServerOption.parseJsonBody;
        settings.bindAddresses = cfg["listenAddresses"].deserializeBson!(string[]);
        settings.port = to!ushort(cfg["listenPort"].get!long);

        auto listenHandler = listenHTTP(settings, &httpRequestHandler);

        runEventLoop();
    }

    return 0;
}

struct RpcRequest
{
    Json id;
    string method;
    string[string] namedParams = null;
    string[] positionParams = null;

    invariant()
    {
        assert(namedParams is null || positionParams is null);
    }

    static RpcRequest toRpcRequest(scope HTTPServerRequest req)
    {
        if(req.contentType != "application/json")
            throw new HttpException("Supported only application/json content type", __FILE__, __LINE__);

        Json j = req.json;

        if(j["jsonrpc"] != "2.0")
            throw new HttpException("Protocol version should be \"2.0\"", __FILE__, __LINE__);

        RpcRequest r;

        r.id = j["id"];
        r.method = j["method"].get!string;

        Json params = j["params"];

        switch(params.type)
        {
            case Json.Type.object:
                foreach(string key, value; params)
                {
                    if(value.type == Json.Type.object || value.type == Json.Type.array)
                        throw new HttpException("Unexpected named parameter type", __FILE__, __LINE__);

                    r.namedParams[key] = value.to!string;
                }
                break;

            case Json.Type.array:
                foreach(value; params)
                {
                    if(value.type == Json.Type.object || value.type == Json.Type.array)
                        throw new HttpException("Unexpected positional parameter type", __FILE__, __LINE__);

                    r.positionParams ~= value.to!string;
                }
                break;

            default:
                throw new HttpException("Unexpected params type", __FILE__, __LINE__);
        }

        return r;
    }
}

class HttpException : Exception
{
    this(string msg, string file, size_t line)
    {
        super(msg, file, line);
    }
}
