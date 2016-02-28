// integration tests
module pgator.test;

version(IntegrationTest)
{
    import std.conv;
    import std.net.curl;

    void main(string[] args)
    {
        string httpHost = args[0];
        string port = args[1];

        HTTP http = HTTP("test client");

        http.url = "http://"~httpHost~":"~port~"/";
        http.method = HTTP.Method.post;
        http.addRequestHeader("Content-Type", "application/json");
    }

    struct QueryAnswer
    {
        size_t line;
        string query;
        string answer;
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

"qwe"
        ),
        QA(__LINE__, "asd", "qwe", 211),
    ];

    foreach(t; tests)
    {
        http.
    }
}
