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

                string resultBody;
                http.onReceive = (ubyte[] data) {
                    resultBody ~= (cast(char[]) data).to!string;
                    return data.length;
                };

                http.perform();

                if(http.statusLine.code != t.httpCode)
                    throw new Exception("HTTP code mismatch: "~http.statusLine.toString~", expected: "~t.httpCode.to!string~"\nResult body:\n"~resultBody, __FILE__, __LINE__);

                Json result = resultBody.parseJsonString;
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
    "result": { "echoed":["123"] },
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
    "result": { "echoed":["123"] }
}
EOS" // FIXME: should be interpereted as notify, without answer
),

QA(__LINE__,
q"EOS
{
    "method": "echo",
    "params": [ 123 ]
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
    "jsonrpc": "2.0",
    "id": 1,
    "method": "one_line",
    "params": ["val1", "val2"]
}
EOS",

q"EOS
{
    "id":1,
    "result":
    {
        "col1":["val1"],
        "col2":["val2"]
    }
}
EOS"
),

QA(__LINE__,
q"EOS
{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "one_line",
    "params": {"arg2": 22, "arg1": 11}
}
EOS",

q"EOS
{
    "id":1,
    "result":
    {
        "col1":["11"],
        "col2":["22"]
    }
}
EOS"
),

QA(__LINE__,
q"EOS
{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "two_lines"
}
EOS",

q"EOS
{
    "id":1,
    "result":
    {
        "column1":[1,2],
        "column2":[3,4],
        "column3":[5,6]
    }
}
EOS"
),

QA(__LINE__,
q"EOS
{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "rotated"
}
EOS",

q"EOS
{
    "id":1,
    "result":
    [
        {"column1":1, "column2":2, "column3":3},
        {"column1":4, "column2":5, "column3":6}
    ]
}
EOS"
)

];
}
