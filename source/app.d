/**
*   Application contains four build configurations: production, unittests, integration test 1,
*   integration test 2 and test client.
*
*   Unittests configuration produce dummy executable the only purpose is to run module unittests.
*
*   Production configuration is main and default configuration. There the configuration files and
*   argument parameters are parsed, daemon or terminal mode is selected and actual rpc server starts.
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

import stdlog;

version(unittest)
{
	void main()
	{
		
	}
}
else version(IntegrationTest1)
{
    import std.getopt;
    import std.stdio;
    import std.range;
    import stdlog;
    import db.pq.libpq;
    import db.pq.connection;
    import db.asyncPool;
    import core.time;
    import core.thread;
    
    int main(string[] args)
    {
        string connString;
        string logName = "test.log";
        uint connCount = 50;
        getopt(args
            , "conn",  &connString
            , "log",   &logName
            , "count", &connCount);
        
        if(connString == "")
        {
            writeln("Please, specify connection string.\n"
                    "Params: --conn=string - connection string to test PostgreSQL connection\n"
                    "        --log=string  - you can rewrite log file location, default 'test.log'\n"
                    "        --count=uint  - number of connections in a pool, default 100\n");
            return 0;
        }
        
        auto logger = new shared CLogger(logName);
        scope(exit) logger.finalize();
        
        auto api = new shared PostgreSQL();
        logger.logInfo("PostgreSQL was inited.");
        auto connProvider = new shared PQConnProvider(logger, api);
        
        auto pool = new shared AsyncPool(logger, connProvider, dur!"seconds"(5), dur!"seconds"(5));
        scope(exit) pool.finalize();
        logger.logInfo("AssyncPool was created.");
        
        pool.addServer(connString, connCount);
        logger.logInfo(text(connCount, " new connections were added to the pool."));
        
        Thread.sleep(dur!"seconds"(30));
        
        logger.logInfo("Test ended. Results:"); 
        logger.logInfo(text("active connections:   ", pool.activeConnections));
        logger.logInfo(text("inactive connections: ", pool.inactiveConnections));
        
        pool.finalize();
        logger.finalize();
        std.c.stdlib.exit(0);
        return 0;
    }
}
else version(IntegrationTest2)
{
    import std.getopt;
    import std.stdio;
    import stdlog;
    import db.pq.libpq;
    import db.pq.connection;
    import db.pq.types.conv;
    import db.asyncPool;
    import core.time;
    import core.thread;
    
    int main(string[] args)
    {
        string connString;
        string logName = "test.log";
        uint connCount = 50;
        getopt(args
            , "conn",  &connString
            , "log",   &logName
            , "count", &connCount);
        
        if(connString == "")
        {
            writeln("Please, specify connection string.\n"
                    "Params: --conn=string - connection string to test PostgreSQL connection\n"
                    "        --log=string  - you can rewrite log file location, default 'test.log'\n"
                    "        --count=uint  - number of connections in a pool, default 100\n");
            return 0;
        }
        
        auto logger = new shared CLogger(logName);
        scope(exit) logger.finalize();
        
        auto api = new shared PostgreSQL();
        logger.logInfo("PostgreSQL was inited.");
        auto connProvider = new shared PQConnProvider(logger, api);
        
        auto pool = new shared AsyncPool(logger, connProvider, dur!"seconds"(1), dur!"seconds"(5));
        scope(failure) pool.finalize();
        logger.logInfo("AssyncPool was created.");
        
        pool.addServer(connString, connCount);
        logger.logInfo(text(connCount, " new connections were added to the pool."));
        
        try
        {
            testConvertions(logger, pool);
        } catch(Throwable e)
        {
            logger.logInfo("Conversion tests are failed!");
            logger.logError(text(e));
        }
        
        pool.finalize();
        logger.finalize();
        std.c.stdlib.exit(0);
        return 0;
    }
}
else version(RpcClient)
{
    import std.getopt;
    import std.stdio;
    import client.client;
    import client.test.testcase;
    import client.test.simple;

    immutable helpStr =
    "JSON-RPC client for testing purposes of main rpc-server.\n"
    "   rpc-proxy-client [arguments]\n\n"
    "   arguments = --host=<string> - rpc-server url"
    "               --conn=<string> - postgres server conn string"
    "               --tableName=<string> - json_rpc table"
    "               --serverpid=<uint> - rpc server pid";
    
    int main(string[] args)
    {
        string host;
        string connString;
        string tableName;
        uint pid;
        bool help = false;
        
        getopt(args,
            "host", &host,
            "help|h", &help,
            "conn", &connString,
            "tableName", &tableName,
            "serverpid", &pid
        );
        
        if(help || host == "" || connString == "" || tableName == "" || pid == 0)
        {
            writeln(helpStr);
            return 1;
        }
        
        auto client = new RpcClient!(SimpleTestCase)(host, connString, tableName, pid);
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
	import core.time;
	import server.server;
	import server.options;
	import server.config;
	
	import daemon;
	import terminal;
	
	alias Tuple!(immutable AppConfig, "config", immutable Options, "options") LoadedConfig;
	
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
	
	int main(string[] args)
	{	
		auto options = new immutable Options(args);
		
		if (options.help)
		{
			writeln(options.helpMsg);
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
            auto logger = new shared CLogger(loadedConfig.config.logname);
            auto app = new shared Application(logger, loadedConfig.options, loadedConfig.config);
            
            enum mainFunc = (string[] args)
            {
                int res;
                do
                {
                    res = app.run;
                } while(receiveTimeout(dur!"msecs"(100), 
                        (shared Application newApp) {app = newApp;}));
                
                return res;
            };
            
            enum termFunc = ()
            {
                app.finalize;
                auto newApp = app.restart;
                send(thisTid, newApp);
            };
                    
            if(options.daemon) 
                return runDaemon(logger, mainFunc, args, termFunc,
                    (){app.finalize;}, (int) {app.logger.reload;});
            else 
                return runTerminal(logger, mainFunc, args, termFunc,
                    (){app.finalize;}, (int) {app.logger.reload;});
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
