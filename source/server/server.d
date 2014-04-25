// Written in D programming language
/**
*
* Contains http logic
*
* Copyright: © 2014 DSoftOut
* License: Subject to the terms of the MIT license, as written in the included LICENSE file.
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
import std.functional;
import std.path;

import vibe.data.bson;
import vibe.http.server;
import vibe.http.router;
import vibe.core.driver;
import vibe.core.core;
import vibe.core.log : setLogLevel, setLogFile, LogLevel;

import json_rpc.request;
import json_rpc.error;
import json_rpc.response;

import server.database;
import server.config;
import server.options;

import util;
import dlogg.log;
import dlogg.strict;

/**
* Main program class
*
* Warning:
*   Don't run at once more than one instance of server. Workaround for vibe.d lack of
*   handler removing relies on that there is one running server at current moment.
*
* Authors: Zaramzan <shamyan.roman@gmail.com>
*/
shared class Application
{
	/// Construct Application from ILogger, Options and AppConfig
	this(shared ILogger logger, immutable Options options, immutable AppConfig config)
	{
		this.mLogger = logger;
		this.options = options;
		this.appConfig = config;
		
		mSettings[this] = new HTTPServerSettings;
        mRouters[this] = new URLRouter;
	}
	
	/// runs the server
	int run()
	in
	{
	    assert(!finalized, "Application was finalized!");
	}
	body
	{	
		if (running) return 0;
		
		logger.logInfo("Running server...");
		
		return startServer();
	}
	
	/// restart the server
	/**
	*  Recreates new application object with refreshed config.
	*  New app reuses old logger, old application is terminated.
	*/
	shared(Application) restart()
    in
    {
        assert(!finalized, "Application was finalized!");
    }
    body
	{	
        try
        {
            auto newConfig = immutable AppConfig(options.configName);

            finalize(false);
            
            return new shared Application(mLogger, options, newConfig);
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
	*  Stops the server from any thread.
	*  Params:
	*  finalizeLog = if true, then inner logger wouldn't be finalized
	*/
	void finalize(bool finalizeLog = true)
	{
	    if(finalized) return;
	    
	    scope(exit) 
	    {
	        if(finalizeLog)
	            logger.finalize();
	        finalized = true;
        }
		logger.logDebug("Called finalize");
		
		scope(failure)
		{
			logger.logError("Can not finalize server");
			
			return;
		}
		
		if (database)
		{
			database.finalize();
			logger.logDebug("Database pool is finalized");
		}
		
		if (running)
		{
			stopServer();
		}
		
		if(this in mSettings)
	    {
	        mSettings.remove(this);
	    }
	    if(this in mRouters)
	    {
	        mRouters.remove(this);
	    }
	}
	
	/// Return current application logger
	shared(ILogger) logger()
    in
    {
        assert(!finalized, "Application was finalized!");
    }
    body
	{
	    return mLogger;
	}
    
    private:
    
	void setupSettings()
	{
		settings.port = appConfig.port;
		
		settings.options = HTTPServerOption.none;
			
		if (appConfig.hostname) 
			settings.hostName = toUnqual(appConfig.hostname.idup);
			
		if (appConfig.bindAddresses)
			settings.bindAddresses =cast(string[]) appConfig.bindAddresses.idup;
		
		setLogLevel(LogLevel.none);
		setLogFile(appConfig.vibelog, LogLevel.info);
		setLogFile(appConfig.vibelog, LogLevel.error);
		setLogFile(appConfig.vibelog, LogLevel.warn);
	}
	
	void setupRouter()
	{
		auto del = cast(HTTPServerRequestDelegate) toDelegate(&handler);
		
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
			
			logger.logDebug("Server error:" ~ to!string(e));
			
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
			currApplication = this;
			return runEventLoop();
		}
		catch(Throwable e)
		{
			logger.logError("Server error: "~e.msg);
			logger.logDebug("Server error:" ~ to!string(e));
			
			finalize();
			return -1;
		}
		
	}
	
	void stopServer()
	{
		logger.logInfo("Stopping event loop");
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
	static void handler(HTTPServerRequest req, HTTPServerResponse res)
    in
    {
        assert(!currApplication.finalized, "Application was finalized!");
    }
    body
	{	
	    with(currApplication)
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
    			string jsonStr;
    			
    			jsonStr = cast(string) req.bodyReader.peek;
    			
    			rpcReq = RpcRequest(tryEx!RpcParseError(jsonStr));
    			
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
    			else if (database.needAuth(rpcReq.method))
    			{
    				throw new HTTPStatusException(HTTPStatus.unauthorized);
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
	}
	
	HTTPServerSettings settings()
	{
	    assert(this in mSettings);
	    return mSettings[this];
	}
	
	void settings(HTTPServerSettings value)
	{
	    assert(this in mSettings);
	    mSettings[this] = value;
	}
	
	URLRouter router()
	{
	    assert(this in mRouters);
	    return mRouters[this];
	}
	
	void router(URLRouter value)
	{
	    assert(this in mRouters);
	    mRouters[this] = value;
	}
	
	ILogger mLogger;
	Database database;
	
	immutable AppConfig appConfig;
	immutable Options options;
	
	int conns;
	bool running;
	bool internalError;
	bool finalized;
	
	private
	{
		__gshared HTTPServerSettings[shared const Application] mSettings;
		__gshared URLRouter[shared const Application] mRouters;
		static shared Application currApplication;
	}
}
