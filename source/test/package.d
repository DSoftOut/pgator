// integration tests
module pgator.test;

import std.conv;
import std.net.curl;

void __integration_test(string httpHost, ushort port)
{
    auto content = post(httpHost~":"~port.to!string~"/", [1,2,3,4]);
}

