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
        
        auto api = new PostgreSQL();
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
        
        auto api = new PostgreSQL();
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
	import std.getopt;
	import std.functional;

	import server.server;
	import server.options;
	import server.config;

	import daemon;
	import terminal;

	int main(string[] args)
	{	
		Options options = new Options(args);

		if (options.help)
		{
			writeln(options.helpMsg);
			return 0;
		}

		if (options.genPath)
		{
			genConfig(options.genPath);

			return 0;
		}

		shared ILogger logger;

		try
		{
			 logger = new shared CLogger(options.logPath);
		}
		catch (Exception e)
		{
			writeln("Can't create log at "~options.logPath);
			return 0;
		}

		shared Application app = new shared Application(logger, options);

		if(options.daemon) 
			return runDaemon(logger, &curry!(progMain, app), args, 
				(){app.restart;}, (){app.finalize;}, (int) {app.logger.reload;});
		else 
			return runTerminal(logger, &curry!(progMain, app), args, 
				(){app.restart;}, (){app.finalize;}, (int) {app.logger.reload;});
	}


	int progMain(shared Application app, string[] args)
	{
		import core.time;
		import core.thread;

		app.run();

		return 0;
	}
}
