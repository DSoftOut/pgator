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

    auto content = post(httpHost~":"~port~"/", [1,2,3,4]);
}

}
