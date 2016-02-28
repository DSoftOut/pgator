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

        HTTP http = HTTP("test client");

        const url = "http://"~httpHost~":"~port~"/";
        http.addRequestHeader("Content-Type", "application/json");

        foreach(t; tests)
        {
            try
            {
                try
                {
                    auto p = post(url, t.query, http);

                    import vibe.data.json;
                    Json result = parseJsonString(p.to!string);
                    Json expected = parseJsonString(t.expectedAnswer);

                    enforce(result == expected, "result: "~result.toString~", expected: "~expected.toString);
                }
                catch(CurlException e)
                {
                    import std.algorithm.searching;

                    if(e.msg.canFind("status code 400 (Bad Request)") && t.httpCode != 400)
                        throw new Exception(e.msg, __FILE__, __LINE__);
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
        QA(__LINE__, "asd", "qwe", 211),
    ];
}
