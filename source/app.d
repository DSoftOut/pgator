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
    import stdlog;
    import db.pq.libpq;
    import db.pq.connection;
    import db.assyncPool;
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
        auto connProvider = new PQConnProvider(logger, api);
        
        auto pool = new AssyncPool(logger, connProvider, dur!"seconds"(1), dur!"seconds"(1));
        scope(exit) pool.finalize(() {});
        logger.logInfo("AssyncPool was created.");
        
        pool.addServer(connString, connCount);
        logger.logInfo(text(connCount, " new connections were added to the pool."));
        
        Thread.sleep(dur!"seconds"(5));
        
        logger.logInfo("Test ended. Results:"); 
        logger.logInfo(text("active connections:   ", pool.activeConnections));
        logger.logInfo(text("inactive connections: ", pool.inactiveConnections));
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
    import db.assyncPool;
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
        
        bool canExit = false;
        auto logger = new shared CLogger(logName);
        scope(exit) logger.finalize();
        
        auto api = new PostgreSQL();
        logger.logInfo("PostgreSQL was inited.");
        auto connProvider = new PQConnProvider(logger, api);
        
        auto pool = new AssyncPool(logger, connProvider, dur!"seconds"(1), dur!"seconds"(5));
        scope(failure) pool.finalize(() {});
        logger.logInfo("AssyncPool was created.");
        
        pool.addServer(connString, connCount);
        logger.logInfo(text(connCount, " new connections were added to the pool."));
        
//        auto results = pool.execQuery("SELECT now() as current_time, 'abc'::text as field_name, "
//                                      "123 as field_3, 728.258 as field_4, $1::int as field_5", ["42"]);
//        
//        logger.logInfo("Test ended. Results:"); 
//        foreach(res; results)
//            logger.logInfo(text(res.asBson));
        
        testConvertions(logger, pool);
        
        pool.finalize(() {canExit = true;});
        while(!canExit) {}
        return 0;
    }
}
else
{
	import std.stdio;
	import std.getopt;
	import daemon;
	import terminal;

	immutable help = `
	Server that transforms JSON-RPC calls in SQL queries for PostgreSQL.
		rpc-proxy-server [arguments]
		
		arguments = --daemon - run in daemon mode (detached from tty). 
						Linux only.
				    --log=<string> - specifies logging file name, 
				    	default is 'rpc-proxy-server.log'.
				    --help - prints this message
	`;
	
	int main(string[] args)
	{
		bool daemon = false;
		bool help = false;
		string logName = args[0]~".log";
		
		try
		{
			getopt(args, std.getopt.config.passThrough,
						 "daemon", &daemon,
					 	 "log", &logName,
					 	 "help", &help);
		} catch(Exception e)
		{
			writeln(e.msg); 
			writeln(help);
			return 0;
		}
		
		if(help)
		{
			writeln(help);
			return 0;
		}
		
		auto logger = new shared CLogger(logName);
		if(daemon) 
			return runDaemon(logger, (nargs) => 0, args, (){});
		else 
			return runTerminal(logger, (nargs) => 0, args, (){});
	}
}