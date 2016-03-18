import pgator.rpc_table;
import std.getopt;
import std.typecons: Tuple;
import vibe.http.server;
import vibe.core.log;
import vibe.data.json;
import vibe.data.bson;
import vibe.db.postgresql;

@trusted:

string configFileName = "/wrong/path/to/file.json";
bool debugEnabled = false;
bool checkMethods = false;

void readOpts(string[] args)
{
    try
    {
        auto helpInformation = getopt(
                args,
                "debug", &debugEnabled,
                "check", &checkMethods,
                "config", &configFileName
            );
    }
    catch(Exception e)
    {
        logFatal(e.msg);
    }

    if(debugEnabled) setLogLevel = LogLevel.debugV;
}

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
        logFatal(e.msg);
        throw e;
    }

    return cfg;
}

private struct PrepareMethodsArgs
{
    const SQLVariablesNames varNames;
    bool methodsLoadedFlag = false; // need for bootstrap
    Method[string] methods;
    size_t rpcTableLength;
    size_t failedCount;
    string tableName;
}

int main(string[] args)
{
    try
    {
        readOpts(args);
        Bson cfg = readConfig();

        auto server = cfg["sqlServer"];
        const connString = server["connString"].get!string;
        auto maxConn = to!uint(server["maxConn"].get!long);

        PrepareMethodsArgs prepArgs = {
            varNames: SQLVariablesNames(
                cfg["sqlAuthVariables"]["username"].get!string,
                cfg["sqlAuthVariables"]["password"].get!string
            )
        };

        // delegate
        void afterConnectOrReconnect(PostgresClient.Connection conn) @safe
        {
            if(prepArgs.methodsLoadedFlag)
            {
                logDebugV("Preparing");
                auto failedMethodsNames = prepareMethods(conn, prepArgs);
                prepArgs.failedCount += failedMethodsNames.length;

                foreach(n; failedMethodsNames)
                    prepArgs.methods.remove(n);

                logInfo("Number of methods in the table "~prepArgs.tableName~": "~
                    prepArgs.rpcTableLength.to!string~", failed to prepare: "~prepArgs.failedCount.to!string);
            }
        }

        // connect to db
        auto client = new PostgresClient(connString, maxConn, &afterConnectOrReconnect);

        {
            auto conn = client.lockConnection();
            auto sqlPgatorTable = cfg["sqlPgatorTable"].get!string;

            // read pgator_rpc
            prepArgs.tableName = conn.escapeIdentifier(sqlPgatorTable);

            QueryParams p;
            p.sqlCommand = "SELECT * FROM "~prepArgs.tableName;
            auto answer = conn.execStatement(p);

            prepArgs.rpcTableLength = answer.length;
            prepArgs.methods = readMethods(answer);
            prepArgs.methodsLoadedFlag = true;

            {
                prepArgs.failedCount = prepArgs.rpcTableLength - prepArgs.methods.length;
                logDebugV("Number of methods in the table "~prepArgs.tableName~": "~prepArgs.rpcTableLength.to!string~", failed to load into pgator: "~prepArgs.failedCount.to!string);
            }

            // prepare statements for previously used connection
            afterConnectOrReconnect(conn);
        }

        if(!checkMethods)
        {
            loop(cfg, client, prepArgs.methods);
        }

        return prepArgs.failedCount ? 2 : 0;
    }
    catch(Exception e)
    {
        logFatal(e.msg);

        return 1;
    }
}

void loop(in Bson cfg, PostgresClient client, in Method[string] methods)
{
    // http-server
    import vibe.core.core;

    void httpRequestHandler(scope HTTPServerRequest req, HTTPServerResponse res)
    {
        try
        {
            RpcRequestResults results = performRpcRequests(methods, client, req);

            if(!results.isBatchMode) // normal mode response
            {
                const result = &results.results[0];

                if(result.exception is null)
                {
                    if(result.isNotify)
                    {
                        res.statusCode = HTTPStatus.noContent;
                        res.writeVoidBody();
                    }
                    else
                    {
                        res.writeJsonBody(result.responseBody);
                    }
                }
                else // error handling
                {
                    if(result.isNotify)
                    {
                        res.statusCode = HTTPStatus.noContent;
                        res.statusPhrase = result.exception.msg;
                        res.writeVoidBody();
                    }
                    else
                    {
                        res.writeJsonBody(result.responseBody, result.exception.httpCode);
                    }
                }
            }
            else // batch mode response
            {
                Bson[] ret;

                foreach(ref r; results.results) // fill response array
                {
                    if(!r.isNotify) // skip notify responses
                        ret ~= r.responseBody;
                }

                if(ret.length)
                {
                    res.writeJsonBody(Bson(ret)); // normal batch response
                }
                else
                {
                    res.statusCode = HTTPStatus.noContent;
                    res.writeVoidBody(); // empty response for batch with notifies only
                }
            }
        }
        catch(LoopException e)
        {
            res.writeJsonBody(Bson(e.msg), e.httpCode); // FIXME: wrong error body format

            logWarn(e.msg);
        }
        catch(Exception e)
        {
            logFatal(e.toString);
        }
    }

    auto settings = new HTTPServerSettings;
    settings.options |= HTTPServerOption.parseJsonBody;
    settings.bindAddresses = cfg["listenAddresses"].deserializeBson!(string[]);
    settings.port = to!ushort(cfg["listenPort"].get!long);

    auto listenHandler = listenHTTP(settings, &httpRequestHandler);

    runEventLoop();
}

struct SQLVariablesNames
{
    string username;
    string password;
}

private struct TransactionQueryParams
{
    QueryParams queryParams;
    AuthorizationCredentials auth;

    alias queryParams this;
}

private immutable(Answer) transaction(PostgresClient client, in Method method, ref TransactionQueryParams qp)
{
    logDebugV("Try to exec transaction with prepared method "~qp.preparedStatementName);

    PostgresClient.Connection conn = client.lockConnection();

    if(method.needAuthVariablesFlag && !qp.auth.authVariablesSet)
        throw new LoopException(JsonRpcErrorCode.invalidParams, HTTPStatus.unauthorized, "Basic HTTP authentication need", __FILE__, __LINE__);

    bool transactionStarted = false;

    if(method.readOnlyFlag) // BEGIN READ ONLY
    {
        QueryParams q;
        q.preparedStatementName = beginROPreparedName;
        conn.execPreparedStatement(q);

        transactionStarted = true;
    }

    scope(success)
    if(transactionStarted) // COMMIT
    {
        QueryParams q;
        q.preparedStatementName = commitPreparedName;
        conn.execPreparedStatement(q);
    }

    scope(failure)
    if(transactionStarted) // ROLLBACK
    {
        QueryParams q;
        q.preparedStatementName = rollbackPreparedName;
        conn.execPreparedStatement(q);
    }

    if(method.needAuthVariablesFlag)
    {
        if(!transactionStarted)
        {
            QueryParams q;
            q.preparedStatementName = beginPreparedName;
            conn.execPreparedStatement(q);

            transactionStarted = true;
        }

        QueryParams q;
        q.preparedStatementName = authVariablesSetPreparedName;
        q.args = [qp.auth.username.toValue, qp.auth.password.toValue];
        conn.execPreparedStatement(q);
    }

    return conn.execPreparedStatement(qp);
}

private Bson execPreparedMethod(
    PostgresClient client,
    in Method method,
    ref RpcRequest rpcRequest
)
{
    TransactionQueryParams qp;
    qp.preparedStatementName = rpcRequest.methodName;
    qp.auth = rpcRequest.auth;

    {
        if(rpcRequest.positionParams.length == 0) // named parameters
        {
            qp.args = named2positionalParameters(method, rpcRequest.namedParams);
        }
        else // positional parameters
        {
            if(rpcRequest.positionParams.length != method.argsNames.length)
                throw new LoopException(JsonRpcErrorCode.invalidParams, HTTPStatus.badRequest, "Parameters number mismatch", __FILE__, __LINE__);

            qp.args = new Value[rpcRequest.positionParams.length];

            foreach(i, ref b; rpcRequest.positionParams)
            {
                auto v = &qp.args[i];

                const oid = method.argsOids[i];
                *v = bsonToValue(b, oid);

                if(v.oidType != oid)
                    throw new LoopException(
                        JsonRpcErrorCode.invalidParams,
                        HTTPStatus.badRequest,
                        "Parameter #"~i.to!string~" type is "~v.oidType.to!string~", but expected "~oid.to!string,
                        __FILE__, __LINE__);
            }
        }
    }

    try
    {
        immutable answer = client.transaction(method, qp);

        Bson getValue(size_t rowNum, size_t colNum)
        {
            string columnName = answer.columnName(colNum);

            try
            {
                return answer[rowNum][colNum].as!Bson;
            }
            catch(AnswerConvException e)
            {
                e.msg = "Column "~columnName~" ("~rowNum.to!string~" row): "~e.msg;
                throw e;
            }
        }

        with(ResultFormat)
        final switch(method.resultFormat)
        {
            case CELL:
            {
                if(answer.length != 1 || answer.columnCount != 1)
                    throw new LoopException(JsonRpcErrorCode.internalError, HTTPStatus.internalServerError, "One cell flag constraint failed", __FILE__, __LINE__);

                return getValue(0, 0);
            }

            case ROW:
            {
                if(answer.length != 1)
                    throw new LoopException(JsonRpcErrorCode.internalError, HTTPStatus.internalServerError, "One row flag constraint failed", __FILE__, __LINE__);

                Bson ret = Bson.emptyObject;

                foreach(colNum; 0 .. answer.columnCount)
                    ret[answer.columnName(colNum)] = getValue(0, colNum);

                return ret;
            }

            case TABLE:
            {
                Bson ret = Bson.emptyObject;

                foreach(colNum; 0 .. answer.columnCount)
                {
                    Bson[] col = new Bson[answer.length];

                    foreach(rowNum; 0 .. answer.length)
                        col[rowNum] = getValue(rowNum, colNum);

                    ret[answer.columnName(colNum)] = col;
                }

                return ret;
            }

            case ROTATED:
            {
                Bson[] ret = new Bson[answer.length];

                foreach(rowNum; 0 .. answer.length)
                {
                    Bson row = Bson.emptyObject;

                    foreach(colNum; 0 .. answer.columnCount)
                        row[answer.columnName(colNum)] = getValue(rowNum, colNum);

                    ret[rowNum] = row;
                }

                return Bson(ret);
            }
        }
    }
    catch(AnswerCreationException e)
    {
        throw new LoopException(JsonRpcErrorCode.internalError, HTTPStatus.internalServerError, e.msg, __FILE__, __LINE__, e);
    }
}

Value[] named2positionalParameters(in Method method, Bson[string] namedParams)
{
    Value[] ret = new Value[method.argsNames.length];

    foreach(i, argName; method.argsNames)
    {
        auto b = argName in namedParams;

        if(b)
        {
            const oid = method.argsOids[i];
            Value v = bsonToValue(*b, oid);

            if(v.oidType != oid)
                throw new LoopException(
                    JsonRpcErrorCode.invalidParams,
                    HTTPStatus.badRequest,
                    argName~" parameter type is "~v.oidType.to!string~", but expected "~oid.to!string,
                    __FILE__, __LINE__);

            ret[i] = v;
        }
        else
        {
            throw new LoopException(JsonRpcErrorCode.invalidParams, HTTPStatus.badRequest, "Missing required parameter "~argName, __FILE__, __LINE__);
        }
    }

    return ret;
}

private struct AuthorizationCredentials
{
    bool authVariablesSet = false;
    string username;
    string password;
}

RpcRequestResults performRpcRequests(in Method[string] methods, PostgresClient client, scope HTTPServerRequest req)
{
    if(req.contentType != "application/json")
        throw new LoopException(JsonRpcErrorCode.invalidRequest, HTTPStatus.unsupportedMediaType, "Supported only application/json content type", __FILE__, __LINE__);

    RpcRequestResults ret;
    Json j = req.json;

    switch(j.type)
    {
        case Json.Type.array:
            if(!j.length)
                throw new LoopException(JsonRpcErrorCode.invalidRequest, HTTPStatus.badRequest, "Empty batch array", __FILE__, __LINE__);

            ret.isBatchMode = true;
            break;

        case Json.Type.object:
            ret.isBatchMode = false;
            break;

        default:
            throw new LoopException(JsonRpcErrorCode.parseError, HTTPStatus.badRequest, "Parse error", __FILE__, __LINE__);
    }

    RpcRequest[] requests;

    if(!ret.isBatchMode)
    {
        requests.length = 1;
        requests[0] = RpcRequest.jsonToRpcRequest(j, req);
    }
    else
    {
        requests.length = j.length;

        foreach(i, ref request; requests)
        {
            request = RpcRequest.jsonToRpcRequest(j[i], req);
        }
    }

    ret.results.length = requests.length;

    foreach(i, ref request; requests)
    {
        ret.results[i] = request.performRpcRequest(methods, client); // TODO: async exec
    }

    return ret;
}

struct RpcRequest
{
    Bson id;
    string methodName;
    Bson[string] namedParams = null;
    Bson[] positionParams = null;
    AuthorizationCredentials auth;

    invariant()
    {
        assert(namedParams is null || positionParams is null);
    }

    bool isNotify() const
    {
        return id.type == Bson.Type.undefined;
    }

    private static RpcRequest jsonToRpcRequest(scope Json j, in HTTPServerRequest req)
    {
        if(j["jsonrpc"] != "2.0")
            throw new LoopException(JsonRpcErrorCode.invalidRequest, HTTPStatus.badRequest, "Protocol version should be \"2.0\"", __FILE__, __LINE__);

        RpcRequest r;

        r.id = j["id"];
        r.methodName = j["method"].get!string;

        Json params = j["params"];

        switch(params.type)
        {
            case Json.Type.undefined: // params omitted
                break;

            case Json.Type.object:
                foreach(string key, value; params)
                {
                    if(value.type == Json.Type.object)
                        throw new LoopException(JsonRpcErrorCode.invalidParams, HTTPStatus.badRequest, "Unexpected named parameter type", __FILE__, __LINE__);

                    r.namedParams[key] = value;
                }
                break;

            case Json.Type.array:
                foreach(value; params)
                {
                    if(value.type == Json.Type.object)
                        throw new LoopException(JsonRpcErrorCode.invalidParams, HTTPStatus.badRequest, "Unexpected positional parameter type", __FILE__, __LINE__);

                    r.positionParams ~= Bson(value);
                }
                break;

            default:
                throw new LoopException(JsonRpcErrorCode.invalidParams, HTTPStatus.badRequest, "Unexpected params type", __FILE__, __LINE__);
        }

        // pick out name and password from the request
        {
            import std.string;
            import std.base64;

            // Copypaste from vibe.d code, see https://github.com/rejectedsoftware/vibe.d/issues/1449
            auto pauth = "Authorization" in req.headers;
            if( pauth && (*pauth).startsWith("Basic ") )
            {
                string user_pw = cast(string)Base64.decode((*pauth)[6 .. $]);

                auto idx = user_pw.indexOf(":");
                enforceBadRequest(idx >= 0, "Invalid auth string format!");

                r.auth.authVariablesSet = true;
                r.auth.username = user_pw[0 .. idx];
                r.auth.password = user_pw[idx+1 .. $];
            }
        }

        return r;
    }

    RpcRequestResult performRpcRequest(in Method[string] methods, PostgresClient client)
    {
        try
        {
            try
            {
                const method = (methodName in methods);

                if(method is null)
                    throw new LoopException(JsonRpcErrorCode.methodNotFound, HTTPStatus.badRequest, "Method "~methodName~" not found", __FILE__, __LINE__);

                RpcRequestResult ret;
                ret.isNotify = isNotify;

                if(!ret.isNotify)
                {
                    ret.responseBody = Bson(["id": id]);
                    ret.responseBody["result"] = client.execPreparedMethod(*method, this);
                }
                else // JSON-RPC 2.0 Notification
                {
                    client.execPreparedMethod(*method, this);
                    ret.responseBody = Bson.emptyObject;
                }

                return ret;
            }
            catch(ConnectionException e)
            {
                throw new LoopException(JsonRpcErrorCode.internalError, HTTPStatus.internalServerError, e.msg, __FILE__, __LINE__);
            }
            catch(PostgresClientTimeoutException e)
            {
                throw new LoopException(JsonRpcErrorCode.internalError, HTTPStatus.internalServerError, e.msg, __FILE__, __LINE__);
            }
            catch(AnswerConvException e)
            {
                throw new LoopException(JsonRpcErrorCode.internalError, HTTPStatus.internalServerError, e.msg, __FILE__, __LINE__);
            }
        }
        catch(LoopException e)
        {
            Bson err = Bson.emptyObject;

            err["id"] = cast() id; // FIXME: remove cast!
            err["message"] = e.msg;
            err["code"] = e.jsonCode;

            if(e.answerException !is null)
            {
                Bson hint =    Bson(e.answerException.resultErrorField(PG_DIAG_MESSAGE_HINT));
                Bson detail =  Bson(e.answerException.resultErrorField(PG_DIAG_MESSAGE_DETAIL));
                Bson errcode = Bson(e.answerException.resultErrorField(PG_DIAG_SQLSTATE));

                err["data"] = Bson([
                    "hint": hint,
                    "detail": detail,
                    "errcode": errcode
                ]);
            }

            RpcRequestResult ret;
            ret.isNotify = isNotify;
            ret.responseBody = err;
            ret.exception = e;

            logWarn(err.toString);

            return ret;
        }
    }
}

private struct RpcRequestResult
{
    Bson responseBody;
    LoopException exception;
    bool isNotify;
}

private struct RpcRequestResults
{
    RpcRequestResult[] results;
    bool isBatchMode;
}

enum JsonRpcErrorCode : short
{
    /// Invalid JSON was received by the server.
    /// An error occurred on the server while parsing the JSON text
    parseError = -32700,

    /// The JSON sent is not a valid Request object.
    invalidRequest = -32600,

    /// Method not found
    methodNotFound = -32601,

    /// Invalid params
    invalidParams = -32602,

    /// Internal error
    internalError = -32603,
}

class LoopException : Exception
{
    const JsonRpcErrorCode jsonCode;
    const HTTPStatus httpCode;
    const AnswerCreationException answerException;

    this(JsonRpcErrorCode jsonCode, HTTPStatus httpCode, string msg, string file, size_t line, AnswerCreationException ae = null) pure
    {
        this.jsonCode = jsonCode;
        this.httpCode = httpCode;
        this.answerException = ae;

        super(msg, file, line);
    }
}

immutable string beginPreparedName = "#b#";
immutable string beginROPreparedName = "#r#";
immutable string commitPreparedName = "#C#";
immutable string rollbackPreparedName = "#R#";
immutable string authVariablesSetPreparedName = "#a#";

/// returns names of unprepared methods
private string[] prepareMethods(PostgresClient.Connection conn, ref PrepareMethodsArgs args)
{
    {
        logDebugV("try to prepare internal statements");

        conn.prepareStatement(beginPreparedName, "BEGIN");
        conn.prepareStatement(beginROPreparedName, "BEGIN READ ONLY");
        conn.prepareStatement(commitPreparedName, "COMMIT");
        conn.prepareStatement(rollbackPreparedName, "ROLLBACK");
        conn.prepareStatement(authVariablesSetPreparedName,
            "SELECT set_config("~conn.escapeLiteral(args.varNames.username)~", $1, true),"~
            "set_config("~conn.escapeLiteral(args.varNames.password)~", $2, true)");

        logDebugV("internal statements prepared");
    }

    string[] failedMethods;

    foreach(ref m; args.methods.byValue)
    {
        logDebugV("try to prepare method "~m.name);

        try
        {
            conn.prepareMethod(m);

            m.argsOids = conn.retrieveArgsTypes(m);

            logDebugV("method ", m.name, " prepared");
        }
        catch(ConnectionException e)
        {
            throw e;
        }
        catch(Exception e)
        {
            logWarn(e.msg, ", skipping preparing of method ", m.name);
            failedMethods ~= m.name;
        }
    }

    return failedMethods;
}

private OidType[] retrieveArgsTypes(PostgresClient.Connection conn, ref Method m)
{
    QueryParams q;
    q.sqlCommand = "SELECT parameter_types::Int4[] FROM pg_prepared_statements WHERE name = $1";
    q.argsFromArray = [m.name];

    auto a = conn.execStatement(q);
    enforce(a.length == 1);
    enforce(a[0].length == 1);

    auto arr = a[0][0].asArray;
    enforce(arr.dimsSize.length == 1);

    OidType[] ret = new OidType[arr.length];

    foreach(i; 0 .. ret.length)
        ret[i] = arr[i].as!Oid.oid2oidType;

    return ret;
}

private void prepareMethod(PostgresClient.Connection conn, in Method method)
{
    conn.prepareStatement(method.name, method.statement);
}
