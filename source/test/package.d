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
    }

    struct QueryAnswer
    {
        string query;
        string answer;
        ushort httpCode = 200;
        string contentType = "application/json";
    }

    alias QA = QueryAnswer;

    QueryAnswer[] tests = [
        QA("asd", "qwe"),
        QA("asd", "qwe", "asd"),
    ];
}
