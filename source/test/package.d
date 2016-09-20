// integration tests
module pgator.test;

version(IntegrationTest)
{
    import std.conv;
    import std.net.curl;
    import std.exception: enforce;
    import etc.c.curl: CurlAuth;
    import vibe.data.json;

    void main(string[] args)
    {
        const string httpHost = args[1];
        const string httpPort = args[2];
        const string httpUrl = "http://"~httpHost~":"~httpPort~"/";

        foreach(t; tests)
        {
            try
            {
                HTTP http = HTTP();
                http.method = HTTP.Method.post;
                http.url = httpUrl;
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

        vibedRESTEmulationTests(httpUrl);
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
    "result": { "echoed":[ 123 ] },
    "jsonrpc": "2.0",
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
    "id": 1,
    "jsonrpc": "2.0"
}
EOS"
),

QA(__LINE__, // missing named parameter test
q"EOS
{
    "jsonrpc": "2.0",
    "method": "echo",
    "id": 1
}
EOS",

q"EOS
{
    "jsonrpc": "2.0",
    "error":
    {
        "message": "Missing required parameter value_for_echo",
        "code": -32602
    },
    "id": 1
}
EOS",
400
),

QA(__LINE__, // positional parameters number is too few test
q"EOS
{
    "jsonrpc": "2.0",
    "method": "one_line",
    "params": ["val1"],
    "id": 1
}
EOS",

q"EOS
{
    "jsonrpc": "2.0",
    "error":
    {
        "message": "Parameters number is too few",
        "code": -32602
    },
    "id": 1
}
EOS",
400
),

QA(__LINE__, // positional parameters number is too big test
q"EOS
{
    "jsonrpc": "2.0",
    "method": "echo",
    "params": [123, 456],
    "id": 1
}
EOS",

q"EOS
{
    "jsonrpc": "2.0",
    "error":
    {
        "message": "Parameters number is too big",
        "code": -32602
    },
    "id": 1
}
EOS",
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
    "jsonrpc": "2.0",
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
    "jsonrpc": "2.0",
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
    "jsonrpc": "2.0",
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
    "jsonrpc": "2.0",
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
    "jsonrpc": "2.0",
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
    "jsonrpc": "2.0",
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
    "jsonrpc": "2.0",
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
    "jsonrpc": "2.0",
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
    {"result":123, "id":1, "jsonrpc": "2.0"},
    {"error": {"message": "Missing required parameter value_for_echo", "code": -32602}, "jsonrpc": "2.0", "id": 2},
    {"result":{"echoed":[123]},"id":3, "jsonrpc": "2.0"}
]
EOS"
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
    "jsonrpc": "2.0",
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
    "jsonrpc": "2.0",
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
    "jsonrpc": "2.0",
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
    "jsonrpc": "2.0",
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

QA(__LINE__, // multi-statement named args method
q"EOS
{
    "jsonrpc": "2.0",
    "method": "multi_tran",
    "params": { "value_1": "abc", "value_2": 777 },
    "id": 1
}
EOS",

q"EOS
{
    "jsonrpc": "2.0",
    "result":
    {
        "first_result": { "column1":[1,2], "column2":[3,4], "column3":[5,6] },
        "second_result": "abc",
        "third_result": 777
    },
    "id": 1
}
EOS"
),


QA(__LINE__, // multi-statement positional args method
q"EOS
{
    "jsonrpc": "2.0",
    "method": "multi_tran",
    "params": [ "abc", 777 ],
    "id": 1
}
EOS",

q"EOS
{
    "jsonrpc": "2.0",
    "result":
    {
        "first_result": { "column1":[1,2], "column2":[3,4], "column3":[5,6] },
        "second_result": "abc",
        "third_result": 777
    },
    "id": 1
}
EOS"
),

QA(__LINE__, // JSON test
q"EOS
{
    "jsonrpc": "2.0",
    "method": "echo_json",
    "params": { "json_value": { "inner_value": { "sub_value": 123 } } },
    "id": 1
}
EOS",

q"EOS
{
    "jsonrpc": "2.0",
    "result": { "inner_value": { "sub_value": 123 } },
    "id": 1
}
EOS"
),

QA(__LINE__, // numeric arg test
q"EOS
{
    "jsonrpc": "2.0",
    "method": "echo_numeric",
    "params": [ "123" ],
    "id": 1
}
EOS",

null,
400
),

QA(__LINE__, // numeric result test
q"EOS
{
    "jsonrpc": "2.0",
    "method": "echo_numeric_result",
    "params": [ "123.456789" ],
    "id": 1
}
EOS",

q"EOS
{
    "jsonrpc": "2.0",
    "result": "123.456789",
    "id": 1
}
EOS"
),

QA(__LINE__, // fixedstring test
q"EOS
{
    "jsonrpc": "2.0",
    "method": "echo_fixedstring",
    "params": [ "12345" ],
    "id": 1
}
EOS",

q"EOS
{
    "jsonrpc": "2.0",
    "result": "12345 ",
    "id": 1
}
EOS"
),

];
}

version(IntegrationTest)
void vibedRESTEmulationTests(string httpUrl)
{
    import vibe.web.rest;

    interface ITest
    {
        string getEchoText(string value_for_echo);
        long getEchoBigint(long value_for_echo);
        double getEchoFloat8(double value_for_echo);
    }

    auto m = new RestInterfaceClient!ITest(httpUrl);

    assert(m.getEchoText("abc") == "abc");
    assert(m.getEchoBigint(123456) == 123456);
    assert(m.getEchoFloat8(123.45) == 123.45);

    //assert(m.getEchoBigint(123.456) == 123.456); //TODO: causes error, need to check this case
}
