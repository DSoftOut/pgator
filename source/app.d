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
	
	import daemon;
	import terminal;
	import util;
	

	immutable helpString = 
    `Server that transforms JSON-RPC calls in SQL queries for PostgreSQL.
        
        rpc-proxy-server [arguments]
		
        arguments = --daemon - run in daemon mode (detached from tty). 
                               Linux only.
                    --log=<string> - specifies logging file name, 
                                     default is 'rpc-proxy-server.log'.
                    --config=<string> - specifies config file path
                    --gen-config=<path> generate default config at path
                    --help - prints this message
	`;
	
	int main(string[] args)
	{
		bool daemon = false;
		bool help = false;
		string logName = args[0]~".log";
		string configPath = null;
		string genPath = null;
		
		try
		{
			getopt(args, std.getopt.config.passThrough,
						 "daemon", &daemon,
					 	 "log", &logName,
					 	 "help", &help,
					 	 "config", &configPath,
					 	 "gen-config", &genPath);
		} catch(Exception e)
		{
			writeln(e.msg); 
			writeln(help);
			return 0;
		}
		
		if(help)
		{
			writeln(helpString);
			return 0;
		}
		
		auto logger = new shared CLogger(logName, DEF_LOG_DIR);
		
		shared Application app = new shared Application(logger, configPath);
		
		if (genPath)
		{
			app.genConfig(genPath);
			
			return 0;
		}
		
		if(daemon) 
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
