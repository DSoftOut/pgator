import call_table;
import std.getopt;
import std.experimental.logger;
import vibe.http.server;
import vibe.db.postgresql;
import dpq2;

shared static this()
{
    sharedLog.fatalHandler = null;
}

string configFileName = "/wrong/path/to/file.json";
bool debugEnabled = false;
bool testStatements = false;

void readOpts(string[] args)
{
    try
    {
        auto helpInformation = getopt(
                args,
                "debug", &debugEnabled,
                "test", &testStatements,
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

    const methods = readMethods(answer);

    size_t failedCount = answer.length - methods.length;

    if(testStatements)
    {
        auto conn = client.lockConnection();
        failedCount += prepareMethods(conn.__conn, methods);
        conn.destroy();

        info("Number of methods in the table ", tableName,": ", answer.length, ", failed to prepare: ", failedCount);

        return !failedCount ? 0 : 1;
    }
    else
    {
        loop(cfg, client, methods);

        assert(false);
    }
}

void loop(in Bson cfg, PostgresClient client, in Method[string] methods)
{
    // http-server
    import vibe.http.router;
    import vibe.core.core;

    void httpRequestHandler(scope HTTPServerRequest req, HTTPServerResponse res)
    {
        RpcRequest rpcRequest;

        try
        {
            rpcRequest = RpcRequest.toRpcRequest(req);

            if(rpcRequest.method !in methods)
                throw new HttpException(HTTPStatus.badRequest, "Method "~rpcRequest.method~" not found", __FILE__, __LINE__);

            {
                // exec prepared statement
                QueryParams qp;
                qp.preparedStatementName = rpcRequest.method;

                string[] posParams;

                if(rpcRequest.positionParams.length == 0)
                    posParams = named2positionalParameters(methods[rpcRequest.method], rpcRequest.namedParams);
                else
                    posParams = rpcRequest.positionParams;

                qp.argsFromArray = posParams;

                auto r = client.execPreparedStatement(qp);
            }

            res.writeJsonBody("it works!");
        }
        catch(HttpException e)
        {
            res.writeJsonBody("error! "~e.msg~" "~"id: "~rpcRequest.id.to!string, e.status);
        }
    }

    auto settings = new HTTPServerSettings;
    settings.options |= HTTPServerOption.parseJsonBody;
    settings.bindAddresses = cfg["listenAddresses"].deserializeBson!(string[]);
    settings.port = to!ushort(cfg["listenPort"].get!long);

    auto listenHandler = listenHTTP(settings, &httpRequestHandler);

    runEventLoop();
}

string[] named2positionalParameters(in Method method, in string[string] namedParams) pure
{
    string[] ret = new string[method.argsNames.length];

    foreach(i, argName; method.argsNames)
    {
        if(argName in namedParams)
            ret[i] = namedParams[argName];
        else
            throw new HttpException(HTTPStatus.badRequest, "Missing required parameter "~argName, __FILE__, __LINE__);
    }

    return ret;
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
            throw new HttpException(HTTPStatus.unsupportedMediaType, "Supported only application/json content type", __FILE__, __LINE__);

        Json j = req.json;

        if(j["jsonrpc"] != "2.0")
            throw new HttpException(HTTPStatus.badRequest, "Protocol version should be \"2.0\"", __FILE__, __LINE__);

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
                        throw new HttpException(HTTPStatus.badRequest, "Unexpected named parameter type", __FILE__, __LINE__);

                    r.namedParams[key] = value.to!string;
                }
                break;

            case Json.Type.array:
                foreach(value; params)
                {
                    if(value.type == Json.Type.object || value.type == Json.Type.array)
                        throw new HttpException(HTTPStatus.badRequest, "Unexpected positional parameter type", __FILE__, __LINE__);

                    r.positionParams ~= value.to!string;
                }
                break;

            default:
                throw new HttpException(HTTPStatus.badRequest, "Unexpected params type", __FILE__, __LINE__);
        }

        return r;
    }
}

class HttpException : Exception
{
    const HTTPStatus status;

    this(HTTPStatus status, string msg, string file, size_t line) pure
    {
        this.status = status;
        super(msg, file, line);
    }
}

/// returns number of failed prepare
private size_t prepareMethods(Connection conn, in Method[string] methods)
{
    size_t failedCount = 0;

    foreach(const m; methods.byValue)
    {
        trace("try to prepare method ", m.name);

        try
        {
            conn.prepareMethod(m);

            trace("method ", m.name, " prepared");
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

    return failedCount;
}

private void prepareMethod(Connection conn, in Method method)
{
    immutable timeoutErrMsg = "Prepare statement: exceeded Posgres query time limit";

    // waiting for socket changes for reading
    if(!conn.waitEndOf(WaitType.READ, dur!"seconds"(5)))
    {
        conn.destroy(); // disconnect
        throw new Exception(timeoutErrMsg, __FILE__, __LINE__);
    }

    conn.sendPrepare(method.name, method.statement, method.argsNames.length);

    bool timeoutNotOccurred = conn.waitEndOf(WaitType.READ, dur!"seconds"(5));

    conn.consumeInput();

    immutable(Result)[] ret;

    while(true)
    {
        auto r = conn.getResult();
        if(r is null) break;
        ret ~= r;
    }

    enforce(ret.length <= 1, "sendPrepare query can return only one Result instance");

    if(!timeoutNotOccurred && ret.length == 0) // query timeout occured and result isn't received
        throw new Exception(timeoutErrMsg, __FILE__, __LINE__);

    ret[0].getAnswer; // result checking
}
