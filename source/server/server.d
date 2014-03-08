// Written in D programming language
/**
*
* Contains http logic
*
* Authors: Zaramzan <shamyan.roman@gmail.com>
*
*/
module server.server;

import core.atomic;

import std.base64;
import std.string;
import std.exception;
import std.stdio;
import std.file;
import std.path;

import vibe.data.bson;
import vibe.http.server;
import vibe.http.router;
import vibe.core.driver;
import vibe.core.core;
import vibe.core.log;

import json_rpc.request;
import json_rpc.error;
import json_rpc.response;

import server.database;
import server.config;
import server.options;

import util;
import log;
import stdlog;

/**
* Main program class
*
* Warning:
*	Don't create more than 1 object, if you want to use with different $(B HTTPServerSettings), 
*	$(B URLRouter) beacuse they are __gshared, that means they are static
*
* Authors: Zaramzan <shamyan.roman@gmail.com>
*/
class Application
{
	shared public:
	
	/// Construct Application from ILogger, Options and AppConfig
	this(shared ILogger logger, immutable Options options, immutable AppConfig config)
	{
		this.mLogger = logger;
		this.options = options;
		this.appConfig = config;
		
		init();
	}
	
	~this()
	{
		finalize();
	}
	
	/// runs the server
	int run()
	{			
		if (running) return 0;
		
		logger.logInfo("Running server...");
		
		return startServer();
	}
	
	/// restart the server
	/**
	*  Recreates new application object with refreshed config.
	*/
	shared(Application) restart()
	{	
        try
        {
            auto newConfig = immutable AppConfig(options.configName);
            auto newLogger = new shared CLogger(newConfig.logname);
            
            return new shared Application(newLogger, options, newConfig);
        }
        catch(InvalidConfig e)
        {
            logger.logError(text("Configuration file at '", e.confPath, "' is invalid! ", e.msg));
            assert(false);
        }
        catch(Exception e)
        {
            logger.logError(text("Failed to load configuration file at '", options.configName, "'! Details: ", e.msg));
            assert(false);
        }
	}
	
	/**
	* Stops the server from any thread
	*/
	void finalize()
	{
	    scope(exit) logger.finalize();
		logger.logInfo("Called finalize");
		
		scope(failure)
		{
			logger.logError("Can not finalize server");
			
			return;
		}
		
		if (database)
		{
			database.finalize();
			logger.logInfo("Connection pool is finalized");
		}
		
		if (running)
		{
			stopServer();
		}
	}
	
	/// Return current application logger
	shared(ILogger) logger()
	{
	    return mLogger;
	}
	
	shared private:
	
	/// initialize resources 
	void init() // called once
	{
		settings = new HTTPServerSettings;
		
		router = new URLRouter;
	}
	
	void setupSettings()
	{
		settings.port = appConfig.port;
		
		settings.errorPageHandler = cast(HTTPServerErrorPageHandler) &errorHandler;
		
		settings.options = HTTPServerOption.parseJsonBody;
		
		auto appConfig = toUnqual(this.appConfig);
			
		if (appConfig.hostname) 
			settings.hostName = appConfig.hostname;
			
		if (appConfig.bindAddresses)
			settings.bindAddresses = appConfig.bindAddresses;
		
		setLogLevel(LogLevel.none);
		setLogFile(appConfig.vibelog, LogLevel.info);
		setLogFile(appConfig.vibelog, LogLevel.error);
		setLogFile(appConfig.vibelog, LogLevel.warn);
	}
	
	void setupRouter()
	{
		auto del = cast(HTTPServerRequestDelegate) &handler;
		
		router.any("*", del);
	}
	
	void setupDatabase()
	{
		database = new shared Database(logger, appConfig);
		
		database.setupPool();
	}
	
	
	void configure()
	{	
		setupDatabase();
		
		try
		{
			database.loadJsonSqlTable();
		}
		catch(Throwable e)
		{
			logger.logError("Server error: "~e.msg);
			
			internalError = true;
		}

		database.createCache();
		setupSettings();
		setupRouter();
	}
	
	int startServer()
	{
		try
		{	
			configure();
			
			listenHTTP(settings, router);
			
			lowerPrivileges();
		
			logger.logInfo("Starting event loop");
			
			running = true;
			
			return runEventLoop();
		}
		catch(Throwable e)
		{
			logger.logError("Server error: "~e.msg);
			
			finalize();
			return -1;
		}
	}
	
	void stopServer()
	{
		logger.logInfo("Stopping event loop");
		
		database.finalize();
		getEventDriver().exitEventLoop();
		
		running = false;
	}
	
	bool ifMaxConn()
	{
		return conns > appConfig.maxConn;
	}
	
	bool hasAuth(HTTPServerRequest req, out string user, out string password)
	{	
		auto pauth = "Authorization" in req.headers;
		
		if( pauth && (*pauth).startsWith("Basic ") )
		{
			string user_pw = cast(string)Base64.decode((*pauth)[6 .. $]);
	
			auto idx = user_pw.indexOf(":");
			enforce(idx >= 0, "Invalid auth string format!");
			user = user_pw[0 .. idx];
			password = user_pw[idx+1 .. $];
	
			
			return true;
		}
		
		return false;
	}
	
	/// handles HTTP requests
	void handler(HTTPServerRequest req, HTTPServerResponse res)
	{	
		atomicOp!"+="(conns, 1);
		
		scope(exit)
		{
			atomicOp!"-="(conns, 1);
		}
		
		enum CONTENT_TYPE = "application/json";
		
		if (ifMaxConn)
		{
			res.statusPhrase = "Reached maximum connections";
			throw new HTTPStatusException(HTTPStatus.serviceUnavailable,
				res.statusPhrase);
		}
		
		if (req.contentType != CONTENT_TYPE)
		{
			res.statusPhrase = "Supported only application/json content type";
			throw new HTTPStatusException(HTTPStatus.notImplemented,
				res.statusPhrase);
		}
		
		RpcRequest rpcReq;
		
		try
		{
			rpcReq = RpcRequest(tryEx!RpcParseError(req.json));
			
			string user = null;
			string password = null;
			
			if (tryEx!RpcInvalidRequest(hasAuth(req, user, password)))
			{
				string[string] map;
				
				rpcReq.auth = map;
				
				enforceEx!RpcInvalidRequest(appConfig.sqlAuth.length >=2, "sqlAuth must have at least 2 elements");
				
				rpcReq.auth[appConfig.sqlAuth[0]] = user;
				
				rpcReq.auth[appConfig.sqlAuth[1]] = password;
			}
			
			if (internalError)
			{				
				res.statusPhrase = "Failed to use table: "~appConfig.sqlJsonTable;
				
				throw new HTTPStatusException(HTTPStatus.internalServerError,
					res.statusPhrase);
			}
			
			auto rpcRes = database.query(rpcReq);
			
			res.writeBody(rpcRes.toJson.toPrettyString, CONTENT_TYPE);
			
			void resetCacheIfNeeded()
			{
				yield();
				
				database.dropcaches(rpcReq.method);	
			}
			
			runTask(&resetCacheIfNeeded);
		
		}
		catch (RpcException ex)
		{
			RpcError error = RpcError(ex);
			
			RpcResponse rpcRes = RpcResponse(rpcReq.id, error);
			
			res.writeBody(rpcRes.toJson.toPrettyString, CONTENT_TYPE);
		}
		
	}
	
	/// vibe error handler
	void errorHandler(HTTPServerRequest req, HTTPServerResponse res, HTTPServerErrorInfo info)
	{
		if (info.code == HTTPStatus.badRequest)
		{
			RpcResponse rpcRes = RpcResponse(Json(null), RpcError(new RpcParseError(info.message)));
			
			res.writeBody(rpcRes.toJson.toPrettyString, "application/json");
		}
		else
		{
			res.writeBody(
				format("%d - %s\n%s", info.code, info.message, info.debugMessage), "text/plain");
		}
	}
	
	shared ILogger mLogger;
	
	immutable AppConfig appConfig;
	immutable Options options;
	
	Database database;
	
	int conns;
	
	bool running;
	
	bool internalError;
	
	__gshared private //dirty
	{	
    	HTTPServerSettings settings;
    	
    	URLRouter router;
	}
}
