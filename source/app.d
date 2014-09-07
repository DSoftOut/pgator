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

version(unittest)
{
    void main() {}
}
else version(IntegrationTest1)
{
    import std.getopt;
    import std.stdio;
    import std.range;
    import dlogg.strict;
    import db.pq.libpq;
    import db.pq.connection;
    import db.async.pool;    
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
        
        auto logger = new shared StrictLogger(logName);
        scope(exit) logger.finalize();
        
        auto api = new shared PostgreSQL(logger);
        logger.logInfo("PostgreSQL was inited.");
        auto connProvider = new shared PQConnProvider(logger, api);
        
        auto pool = new shared AsyncPool(logger, connProvider, dur!"seconds"(5), dur!"seconds"(5), dur!"seconds"(3));
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
    import std.exception;
    import dlogg.strict;
    import db.pq.libpq;
    import db.pq.connection;
    import db.pq.types.conv;
    import db.async.pool;    
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
        
        auto logger = new shared StrictLogger(logName);
        scope(exit) logger.finalize();
        
        auto api = new shared PostgreSQL(logger);
        logger.logInfo("PostgreSQL was inited.");
        auto connProvider = new shared PQConnProvider(logger, api);
        
        auto pool = new shared AsyncPool(logger, connProvider, dur!"seconds"(1), dur!"seconds"(5), dur!"seconds"(3));
        scope(failure) pool.finalize();
        logger.logInfo("AssyncPool was created.");
        
        pool.addServer(connString, 1);
        logger.logInfo(text(1, " new connections were added to the pool."));
        
        logger.logInfo("Testing rollback...");
        assertThrown(pool.execTransaction(["select * from;"]));
        
        try
        {
            pool.execTransaction(["select 42::int8 as test_field;"]);
        } catch(QueryProcessingException e)
        {
            assert(false, "Transaction wasn't rollbacked! All queries after block are ignored!");
        }
        
        pool.addServer(connString, connCount-1);
        logger.logInfo(text(connCount-1, " new connections were added to the pool."));
        logger.logInfo("Testing binary protocol...");
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
    
    immutable helpStr =
    "JSON-RPC client for testing purposes of main rpc-server.\n"
    "   rpc-proxy-client [arguments]\n\n"
    "   arguments = --host=<string> - rpc-server url\n"
    "               --conn=<string> - postgres server conn string\n"
    "               --tableName=<string> - json_rpc table\n"
    "               --serverpid=<uint> - rpc server pid\n";
    
    uint getPid()
    {
        return parse!uint(executeShell("[ ! -f /var/run/pgator/pgator.pid ] || echo `cat /var/run/pgator/pgator.pid`").output);
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
                writeln("Failed: ", e.msg);
                return 1;
            }
        }
        
        auto client = new RpcClient!(
        	SimpleTestCase, 
        	NullTestCase,
        	NumericTestCase,
        	UnicodeTestCase,
        	MulticommandCase
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
	import core.time;
	import server.server;
	import server.options;
	import server.config;
	
	import daemon;
	import terminal;
	import dlogg.strict;
	
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

            if(options.daemon) 
                return runDaemon(logger, mainFunc, args, termFunc
                    , (){app.finalize;}, () {app.logger.reload;}
                    , options.pidFile, options.lockFile
                    , loadedConfig.config.groupid, loadedConfig.config.userid);
            else 
                return runTerminal(logger, mainFunc, args, termFunc
                    , (){app.finalize;}, () {app.logger.reload;}
                    , loadedConfig.config.groupid, loadedConfig.config.userid);
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
