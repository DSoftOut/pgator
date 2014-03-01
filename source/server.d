// Written in D programming language
/**
*
* Contains http logic
*
* Authors: Zaramzan <shamyan.roman@gmail.com>
*
*/
module server;

import core.atomic;

import std.base64;
import std.string;
import std.exception;

import vibe.data.bson;
import vibe.http.server;
import vibe.http.router;
import vibe.core.driver;
import vibe.core.core;
import vibe.core.log;

import json_rpc.request;
import json_rpc.error;
import json_rpc.response;

import database;
import config;
import util;
import log;

class Application
{
	shared public:
	
	this(shared ILogger logger, string configPath = CONFIG_PATH)
	{
		this.logger = logger;
		
		this.configPath = configPath;
		
		init();
	}
	
	~this()
	{
		finalize();
	}
	
	/// runs the server
	void run()
	{			
		if (running) return;
		
		logger.logInfo("Running server...");
		
		startServer();
	}
	
	/// restart the server
	void restart()
	{
		stopServer();
		
		run();
	}
	
	/**
	* Stops the server from any thread
	*/
	void finalize()
	{
		logger.logInfo("Called finalize");
		
		scope(failure)
		{
			logger.logError("Can not finalize server");
			
			return;
		}
		
		if (database)
		{
			database.finalizePool();
			logger.logInfo("Connection pool is finalized");
		}
		
		if (running)
		{
			stopServer();
		}
	}
	
	shared private:
	
	/// initialize resources
	// called once
	void init()
	{
		settings = new HTTPServerSettings;
		
		router = new URLRouter;
	}
	
	bool loadAppConfig()
	{
		try
		{
			appConfig = toShared(AppConfig(configPath));
			
			return true;
		}
		catch (InvalidConfig e)
		{
			logger.logError("Bad config. "~e.msg);
		}
		catch (ErrnoException e)
		{
			logger.logError("Config not found. "~e.msg);
		}
		
		return false;
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
		
		setLogFile("./logs/http.log", LogLevel.info);
		setLogFile("./logs/http.log", LogLevel.error);
		setLogFile("./logs/http.log", LogLevel.warn);
	}
	
	void setupRouter()
	{
		auto del = cast(HTTPServerRequestDelegate) &handler;
		
		router.any("*", del);
	}
	
	bool setupDatabase()
	{
		try
		{
			database = new shared Database(logger, appConfig);
			
			database.setupPool();
			
			return true;
		}
		catch (Throwable e)
		{
			logger.logError("Database error:"~e.msg);
		}
		
		return false;
	}
	
	void configure()
	{
		enforce(loadAppConfig, "Failed to load config");
		
		enforce(setupDatabase, "Failed to use database");
		
		setupSettings();
		
		setupRouter();
	}
	
	void startServer()
	{
		try
		{	
			configure();
			
			listenHTTP(settings, router);
			
			logger.logInfo("Starting event loop");
			
			running = true;
			
			runEventLoop();
		}
		catch(Throwable e)
		{
			logger.logError("Server error:"~to!string(e));
			
			finalize();
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
			res.statusCode = HTTPStatus.serviceUnavailable;
			return;
		}
		
		if (req.contentType != CONTENT_TYPE)
		{
			res.statusCode = HTTPStatus.notImplemented;
			return;
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
	
	ILogger logger;
	
	string configPath;
	
	AppConfig appConfig;
	
	Database database;
	
	int conns;
	
	bool running;
	
	__gshared private:
	
	HTTPServerSettings settings;
	
	URLRouter router;
}
