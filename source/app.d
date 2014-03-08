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
        uint connCount = 100;
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
        uint connCount = 100;
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
        
        testConvertions(logger, pool);
        
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
