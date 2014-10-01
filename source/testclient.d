/**
*	Application contains four build configurations: production, unittests and test client.
*
*   Test client is most general integration tests set. First client expects that there is an instance
*   of production configuration is running already. The '--host' argument specifies URL the server is
*   binded to (usually 'http://localhost:8080). The '--serverpid' argument should hold the server 
*   process PID to enable automatic server reloading while changing json-rpc table. '--conn' and
*   '--tableName' specifies connection string to PostgreSQL and json-rpc table respectively that are 
*   used in server being tested.
*
*   Test client performs automatic rules addition to json-rpc table, testing request sending to
*   the production server and checking returned results. Finally test client cleans up used
*   testing rules in json-rpc table.
*
*   Copyright: © 2014 DSoftOut
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*            Zaramzan <shamyan.roman@gmail.com>
*/
module testclient;

version(RpcClient):

import std.getopt;
import std.process;
import std.conv;
import std.stdio;
import client.client;
import client.test.testcase;
import client.test.simple;
import client.test.nullcase;
import client.test.numeric;
import client.test.unicode;
import client.test.multicommand;
import client.test.longquery;
import client.test.notice;

immutable helpStr =
"JSON-RPC client for testing purposes of main rpc-server.\n"
"   pgator-client [arguments]\n\n"
"   arguments = --host=<string> - rpc-server url\n"
"               --conn=<string> - postgres server conn string\n"
"               --tableName=<string> - json_rpc table\n"
"               --serverpid=<uint> - rpc server pid\n";

uint getPid()
{
    return parse!uint(executeShell("[ ! -f /var/run/pgator/pgator.pid ] || echo `cat /var/run/pgator/pgator.pid`").output);
}

// Getting pid via pgrep
uint getPidConsole()
{
    return parse!uint(executeShell("pgrep pgator").output);
}

int main(string[] args)
{
    string host = "http://127.0.0.1:8080";
    string connString;
    string tableName = "json_rpc";
    uint pid;
    bool help = false;
    
    getopt(args,
        "host", &host,
        "help|h", &help,
        "conn", &connString,
        "tableName", &tableName,
        "serverpid", &pid
    );
    
    if(help || connString == "")
    {
        writeln(helpStr);
        return 1;
    }
    
    if(pid == 0)
    {
        writeln("Trying to read pid file at '/var/run/pgator/pgator.pid'");
        try pid = getPid();
        catch(Exception e)
        {
            writeln("Trying to read pid with pgrep");
            try pid = getPidConsole();
            catch(Exception e)
            {
                writeln("Cannot find pgator process!");
                return 1;
            }
        }
    }
    
    auto client = new RpcClient!(
    	SimpleTestCase, 
    	NullTestCase,
    	NumericTestCase,
    	UnicodeTestCase,
    	MulticommandCase,
    	NoticeTestCase,
    	LongQueryTestCase,
    	)(host, connString, tableName, pid);
    scope(exit) client.finalize;
    
    client.runTests();
    
    return 0;
}