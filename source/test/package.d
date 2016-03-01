// integration tests
module pgator.test;

version(IntegrationTest)
{
    import std.conv;
    import std.net.curl;

    void main(string[] args)
    {
        string httpHost = args[1];
        string port = args[2];

        HTTP http = HTTP();
        http.method = HTTP.Method.post;
        http.url = "http://"~httpHost~":"~port~"/";
        http.addRequestHeader("Content-Type", "application/json");

        foreach(t; tests)
        {
            try
            {
                import vibe.data.json;

                http.postData = parseJsonString(t.query).toString;

                Json result;
                http.onReceive = (ubyte[] data) {
                    result = (cast(const(char)[]) data).to!string.parseJsonString;
                    return data.length;
                };

                http.perform();

                if(http.statusLine.code != t.httpCode)
                    throw new Exception("HTTP code mismatch: "~http.statusLine.toString~", expected: "~t.httpCode.to!string~". Result body: "~result.toString, __FILE__, __LINE__);

                Json expected = parseJsonString(t.expectedAnswer);

                enforce(result == expected, "result: "~result.toString~", expected: "~expected.toString);
            }
            catch(Exception e)
            {
                e.msg = "Test line "~t.line.to!string~": "~e.msg;
                throw e;
            }
        }
    }

    struct QueryAnswer
    {
        size_t line;
        string query;
        string expectedAnswer;
        ushort httpCode = 200;
        string contentType = "application/json";
    }

    alias QA = QueryAnswer;

    QueryAnswer[] tests = [
QA(__LINE__,
q"EOS
{
    "jsonrpc": "2.0",
    "method": "echo",
    "params": [ 123 ],
    "id": 1
}
EOS",

q"EOS
{
    "echoed":["123"],
    "id": 1
}
EOS"
),

QA(__LINE__,
q"EOS
{
    "jsonrpc": "2.0",
    "method": "echo",
    "params": [ 123 ],
}
EOS",

q"EOS
{
    "echoed":["123"],
}
EOS" // FIXME: should be empty answer only with HTTP code
),

QA(__LINE__,
q"EOS
{
    "method": "echo",
    "params": [ 123 ],
}
EOS",

q"EOS
{"code":-32600, "message":"Protocol version should be \"2.0\""}
EOS", // FIXME: should be empty answer only with HTTP code
400
),

QA(__LINE__,
q"EOS
{
    "method": "one_row_flag",
    "params": [],
}
EOS",

q"EOS
{"code":-32600, "message":"Protocol version should be \"2.0\""}
EOS", // FIXME: should be empty answer only with HTTP code
400
)

];
}


//one_row_flag
