/**
*   Application contains four build configurations: production, unittests, integration test 1,
*   integration test 2 and test client.
*
*   Unittests configuration produce dummy executable the only purpose is to run module unittests.
*
*   Production configuration is main and default configuration. There the configuration files and
*   argument parameters are parsed and actual rpc server starts.
*
*   Integration test 1 performs simple tests on real PostgreSQL instance. The configuration expects
*   '--conn' parameter with valid connection string to test database. The main thing that is tested
*   is connection pool operational correctness.
*
*   Integration test 2 performs major tests on real PostgreSQL instance. The configuration expects
*   '--conn' parameter with valid connection string to test database. There are many tests for
*   binary converting from libpq format. This test is the most important one as it should expose
*   libp binary format changing while updating to new versions. 
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
module app;

version(unittest)
{
    void main() {}
}
else version(RpcClient)
{
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
    import client.test.singlequery;
    import client.test.onerow;
    import client.test.array;
    import client.test.timestamp;
    
    immutable helpStr =
    "JSON-RPC client for testing purposes of main rpc-server.\n"
    "   pgator-client [arguments]\n\n"
    "   arguments = --host=<string> - rpc-server url\n"
    "               --conn=<string> - postgres server conn string\n"
    "               --tableName=<string> - json_rpc table\n"
    "               --serverpid=<uint> - rpc server pid\n";
    
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
	    writeln("Trying to read pid with pgrep");
	    try pid = getPidConsole();
	    catch(Exception e)
	    {
		writeln("Cannot find pgator process!");
		return 1;
	    }
        }
        
        auto client = new RpcClient!(
        	SimpleTestCase, 
        	NullTestCase,
        	TimestampCase,
        	NumericTestCase,
        	UnicodeTestCase,
        	MulticommandCase,
        	NoticeTestCase,
        	SingleQueryTestCase,
        	OneRowTestCase,
        	ArrayTestCase,
        	LongQueryTestCase,
        	)(host, connString, tableName, pid);
        scope(exit) client.finalize;
        
        client.runTests();
        
        return 0;
    }
}
else
{
    import std.stdio;
    import std.typecons;
    import std.concurrency;
    import std.process;
    import std.string;
	import core.time;
	import server.server;
	import server.options;
	import server.config;
	
	import terminal;
	import dlogg.strict;
	import util;
	
	immutable struct LoadedConfig
    {
        AppConfig config;
        Options options;
    }
    
	LoadedConfig loadConfig(immutable Options options)
	{
        if(options.configName != "")
        {
            return LoadedConfig(immutable AppConfig(options.configName), options);
        }
        else
        {
            auto res = tryConfigPaths(options.configPaths); 
            return LoadedConfig(res.config, options.updateConfigPath(res.path));
        }
	}
	
	/**
	*  Converts group and user names to corresponding gid and uid. If the $(B groupName) or
	*  $(B userName) are already a ints, simply converts them and returns.
	*
	*  Retrieving of user id is performed by 'id -u %s' and group id by 'getent group %s | cut -d: -f3'.
	*/
	Tuple!(int, int) resolveRootLowing(shared ILogger logger, string groupName, string userName)
	{
	    int tryConvert(string what)(string s, string command)
	    {
	        enum warningMsg = "Failed to retrieve " ~ what ~ " id for root lowing: ";
	        int handleFail(lazy string msg)
	        {
	            logger.logWarning(text(warningMsg, msg));
                return -1;
	        }
	        
	        try return s.to!int;
	        catch(ConvException e)
	        {
	            try
	            {
	                auto res = executeShell(command.format(s));
	                if(res.status != 0) return handleFail(res.output);
	                
	                try return res.output.parse!int;
	                catch(ConvException e) return handleFail(e.msg);
                } 
	            catch(ProcessException e) return handleFail(e.msg);
	            catch(StdioException e) return handleFail(e.msg);
	        }
	    }
	    
	    return tuple(tryConvert!"group"(groupName, "getent group %s | cut -d: -f3")
	               , tryConvert!"user"(userName, "id -u %s"));
	}
	
	int main(string[] args)
	{	
		auto options = new immutable Options(args);
		
		if (options.help)
		{
			writeln(options.helpMsg);
			return 0;
		}
		if (options.showVersion)
		{
		    writeln(options.versionMsg);
		    return 0;
		}
		
		if (options.genConfigPath != "")
		{
			genConfig(options.genConfigPath);
			return 0;
		}
		
		try
		{
		    auto loadedConfig = loadConfig(options);
            auto logger = new shared StrictLogger(loadedConfig.config.logname, StrictLogger.Mode.Append);
            auto app = new shared Application(logger, loadedConfig.options, loadedConfig.config);
            
            enum mainFunc = (string[] args)
            {
                int res;
                do
                {
                    res = app.run;
                } while(receiveTimeout(dur!"msecs"(1000), 
                        // bug, should be fixed in 2.067
                        //  (shared(Application) newApp) {app = newApp;}
                        (Variant v) 
                        {
                            auto newAppPtr = v.peek!(shared(Application)); assert(newAppPtr);
                            app = *newAppPtr;
                        }));
                
                logger.logDebug("Exiting main");
                return res;
            };
            
            enum termFunc = ()
            {
                auto newApp = app.restart;
                send(thisTid, newApp);
            };

            int groupid, userid;
            tie!(groupid, userid) = resolveRootLowing(logger, loadedConfig.config.groupid, loadedConfig.config.userid);
            
	    return runTerminal(logger, mainFunc, args, termFunc
		, (){app.finalize;}, () {app.logger.reload;}
		, groupid, userid);
	    }
	    catch(InvalidConfig e)
        {
            writeln("Configuration file at '", e.confPath, "' is invalid! ", e.msg);
            return 1;
        }
        catch(NoConfigLoaded e)
        {
            writeln(e.msg);
            return 1;
        }
        catch(Exception e)
        {
            writeln("Failed to load configuration file at '", options.configName, "'! Details: ", e.msg);
            return 1;
        }
	}
}
