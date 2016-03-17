// integration tests
module pgator.test;

version(IntegrationTest)
{
    import std.conv;
    import std.net.curl;
    import etc.c.curl: CurlAuth;
    import vibe.data.json;

    void main(string[] args)
    {
        const string httpHost = args[1];
        const string port = args[2];

        foreach(t; tests)
        {
            try
            {
                HTTP http = HTTP();
                http.method = HTTP.Method.post;
                http.url = "http://"~httpHost~":"~port~"/";
                http.addRequestHeader("Content-Type", "application/json");

                http.postData = parseJsonString(t.query).toString;

                if(t.username.length)
                {
                    http.authenticationMethod(CurlAuth.basic);
                    http.setAuthentication(t.username, t.password);
                }

                string resultBody;
                http.onReceive = (ubyte[] data) {
                    resultBody ~= (cast(char[]) data).to!string;
                    return data.length;
                };

                http.perform();

                if(http.statusLine.code != t.httpCode)
                    throw new Exception("HTTP code mismatch: "~http.statusLine.toString~", expected: "~t.httpCode.to!string~"\nResult body:\n"~resultBody, __FILE__, __LINE__);

                // Special valid case: expected is empty
                if(t.expectedAnswer.length != 0)
                {
                    Json result = resultBody.parseJsonString;
                    Json expected = parseJsonString(t.expectedAnswer);
                    enforce(result == expected, "result: "~result.toString~", expected: "~expected.toString);
                }
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
        string username;
        string password;
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
    "result": { "echoed":[123] },
    "id": 1
}
EOS"
),

QA(__LINE__,
q"EOS
{
    "jsonrpc": "2.0",
    "method": "echo",
    "params": [ null ],
    "id": 1
}
EOS",

q"EOS
{
    "result": { "echoed": [null] },
    "id": 1
}
EOS"
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
    "params": {"arg2": "22", "arg1": "11"}
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
    "method": "one_row_flag"
}
EOS",

q"EOS
{
    "id":1,
    "result":
    {
        "col1":"val1",
        "col2":"val2"
    }
}
EOS"
),

QA(__LINE__,
q"EOS
{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "one_cell_flag"
}
EOS",

q"EOS
{
    "id":1,
    "result": 123
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
),

QA(__LINE__, // notification test
q"EOS
{
    "jsonrpc": "2.0",
    "method": "echo",
    "params": [ 123 ],
}
EOS",

"", // empty body
204
),

QA(__LINE__, // failed notification test
q"EOS
{
    "jsonrpc": "2.0",
    "method": "echo"
}
EOS",

null,
204
),

QA(__LINE__,
q"EOS
{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "read_only"
}
EOS",

null,
500
),

QA(__LINE__, // transaction completion check
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
    "result": { "echoed":[123] },
    "id": 1
}
EOS"
),

QA(__LINE__, // successful auth test
q"EOS
{
    "jsonrpc": "2.0",
    "method": "echo_auth_variables",
    "id": 1
}
EOS",

q"EOS
{
    "result":
    {
        "user":"test user",
        "pass":"test password"
    },
    "id": 1
}
EOS",
200,
"application/json",
"test user",
"test password"
),

QA(__LINE__, // failed auth test
q"EOS
{
    "jsonrpc": "2.0",
    "method": "echo_auth_variables",
    "id": 1
}
EOS",
null,
401
),

QA(__LINE__, // batch mode test
q"EOS
[
    {
        "jsonrpc": "2.0",
        "method": "one_cell_flag",
        "id": 1
    },
    {
        "jsonrpc": "2.0",
        "method": "echo",
        "id": 2
    },
    {
        "jsonrpc": "2.0",
        "method": "echo",
        "params": [ 123 ],
        "id": 3
    },
    {
        "jsonrpc": "2.0",
        "method": "one_cell_flag",
        "params": [ 456 ]
    }
]
EOS",

q"EOS
[
    {"result":123, "id":1},
    {"message":"Missing required parameter value_for_echo","id":2,"code":-32602},
    {"result":{"echoed":[123]},"id":3}
]
EOS"
),

QA(__LINE__, // RECORD test
q"EOS
{
    "jsonrpc": "2.0",
    "method": "record_returning",
    "id": 1
}
EOS",

null,
500
),

QA(__LINE__, // array test
q"EOS
{
    "jsonrpc": "2.0",
    "method": "echo_array",
    "params": { "arr_value": [[123, 456], [null, 789]] },
    "id": 1
}
EOS",

q"EOS
{
    "result": { "echoed": [[123, 456], [null, 789]] },
    "id": 1
}
EOS"
),

QA(__LINE__, // empty array test
q"EOS
{
    "jsonrpc": "2.0",
    "method": "echo_array",
    "params": { "arr_value": [] },
    "id": 1
}
EOS",

q"EOS
{
    "result": { "echoed": [] },
    "id": 1
}
EOS"
),

QA(__LINE__, // null values array test
q"EOS
{
    "jsonrpc": "2.0",
    "method": "echo_array",
    "params": { "arr_value": [null, null] },
    "id": 1
}
EOS",

q"EOS
{
    "result": { "echoed": [null, null] },
    "id": 1
}
EOS"
),

QA(__LINE__, // null array test
q"EOS
{
    "jsonrpc": "2.0",
    "method": "echo_array",
    "params": { "arr_value": null },
    "id": 1
}
EOS",

q"EOS
{
    "result": { "echoed": null },
    "id": 1
}
EOS"
),

QA(__LINE__, // named param array type failed test
q"EOS
{
    "jsonrpc": "2.0",
    "method": "echo_array",
    "params": { "arr_value": [null, "wrong_value_type"] },
    "id": 1
}
EOS",

null,
400
),

QA(__LINE__, // positional param array type failed test
q"EOS
{
    "jsonrpc": "2.0",
    "method": "echo_array",
    "params": [ [null, "wrong_value_type"] ],
    "id": 1
}
EOS",

null,
400
),

];
}
