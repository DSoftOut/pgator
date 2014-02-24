// Written in D programming language
/**
*
* Contains http logic
*
* Authors: Zaramzan <shamyan.roman@gmail.com>
*
*/
module server;

import std.base64;
import std.string;
import std.exception;
import std.functional;
import std.concurrency;

import vibe.data.bson;
import vibe.http.server;
import vibe.http.router;
import vibe.core.driver;
import vibe.core.core;

import json_rpc.request;
import json_rpc.error;
import json_rpc.response;

import database;
import cache;
import config;
import util;
import log;
import sql_json;

private enum MESSAGE
{
	START,
	
	STOP,
	
	RESTART,
	
	EXIT
}


private void runLoop(shared Application app)
{
	return app.runLoop();
}


private void startVibe(shared Application app)
{
	return app.runVibeLoop();
}


shared class Application
{		
	this(shared ILogger logger)
	{
		this.logger = logger;
	}
	
	~this()
	{
		if (wasRun) send(toUnqual(tid), MESSAGE.EXIT);
	}
	
	
	void finalize()
	{
		if (!wasRun) return;
		
		send(toUnqual(tid), MESSAGE.EXIT);
		
		receiveOnly!bool;
	}
	
	void run()
	{
		auto runTid = spawn(&server.runLoop, this);
		
		send(runTid, MESSAGE.START);
	}
	
	void start()
	{
		if (!wasRun) throw new Exception("Server wasn't run");
		
		send(toUnqual(tid), MESSAGE.START);
	}
	
	void stop()
	{
		send(toUnqual(tid), MESSAGE.STOP);
	}
	
	void restart()
	{
		send(toUnqual(tid), MESSAGE.RESTART);
	}
	
	
	private void runLoop()
	{
		tid = toShared(thisTid);
		
		wasRun = true;
		
		MESSAGE msg;
		
		bool exit;
		while(!exit)
		{
			msg = receiveOnly!MESSAGE;
		
			final switch (msg)
			{
				case MESSAGE.RESTART:
					stopVibe();
					startVibe();
					continue;
					
				case MESSAGE.STOP:
					stopVibe();
					continue;
					
				case MESSAGE.START:
					startVibe();
					continue;
					
				case MESSAGE.EXIT:
					stopVibe();
					send(ownerTid, true);
					return;
			}
		}
	}
	
	/// setups settings and router
	private void init()
	{
		settings = toShared(new HTTPServerSettings());
		
		router = toShared(new URLRouter());
	}
	
	private void loadConfig()
	{
		appConfig = toShared(AppConfig(CONFIG_PATH));
	}
	
	private void setup()
	{
		init();
		
		loadConfig();
		
		database = new shared Database(logger, appConfig); //because config may change
		
		database.setupPool();
		
		setupSettings();
		
		setupRouter();
	}
	
	package void runVibeLoop()
	{
		setup();
		
		listenHTTP(cast(HTTPServerSettings)settings, cast(URLRouter) router);
		
		logger.logInfo("Starting vibe loop");
		
		runEventLoop();
	}
	
	package void startVibe()
	{
		auto mtid = spawn(&server.startVibe, this);
		
		register("startVibe", mtid);
	}
	
	private void stopVibe()
	{
		bool exit;
		
		database.finalizePool((){ logger.logInfo("Finalized pool"); exit = true;});
		
		while(!exit){}
		
		logger.logInfo("Stopping vibe loop");
		
		getEventDriver().exitEventLoop();
	}
	
	private void setupSettings()
	{
		auto settings = toUnqual(settings);
		auto appConfig = toUnqual(appConfig);
		
		settings.port = appConfig.port;
		
		settings.errorPageHandler = cast(HTTPServerErrorPageHandler) &errorHandler;
		
		settings.options = HTTPServerOption.parseJsonBody;
			
		if (appConfig.hostname) 
			settings.hostName = appConfig.hostname;
			
		if (appConfig.bindAddresses)
			settings.bindAddresses = appConfig.bindAddresses;
	}
	
	private void setupRouter()
	{	
		auto router = toUnqual(router);
		
		auto del = cast(void delegate(HTTPServerRequest, HTTPServerResponse))(&handler);
		
		router.any("*", del);
		
	}
	
	//Заглушка
	private bool ifMaxConn() @property
	{
		return false;
	}
	
	
	private bool hasAuth(HTTPServerRequest req, out string user, out string password)
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
	private void handler(HTTPServerRequest req, HTTPServerResponse res)
	{
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
			
			logger.logInfo("Querying...");
			
			auto rpcRes = database.query(rpcReq);
			
			res.writeBody(rpcRes.toJson.toPrettyString, CONTENT_TYPE);
			
			void resetCacheIfNeeded()
			{
				yield();
				database.dropcaches(rpcReq.method);
				logger.logInfo("After task finished");
				
			}
			
			runTask(&resetCacheIfNeeded);
			
			logger.logInfo("Task loaded");
		
		}
		catch (RpcException ex)
		{
			RpcError error = RpcError(ex);
			
			RpcResponse rpcRes = RpcResponse(rpcReq.id, error);
			
			res.writeBody(rpcRes.toJson.toPrettyString, CONTENT_TYPE);
		}
		
	}
	
	private void errorHandler(HTTPServerRequest req, HTTPServerResponse res, HTTPServerErrorInfo info)
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
	
	private HTTPServerSettings settings;

	private URLRouter router;
	
	private AppConfig appConfig; //create with setup()
	
	private ILogger logger;
	
	private Tid tid;
	
	private Database database; //create with setup()
	
	private bool wasRun;
}

