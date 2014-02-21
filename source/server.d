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

import core.thread;

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

enum MESSAGE
{
	START,
	
	STOP,
	
	RESTART,
	
	EXIT
}

//dirty
void run(shared Application app)
{
	return app.run();
}

//dirty
void startVibe(shared Application app)
{
	return app.runVibeLoop();
}


shared class Application
{		
	this(shared ILogger logger)
	{
		this.logger = logger;
		
		init();
	}
	
	~this()
	{
		if (hadRun) send(toUnqual(tid), MESSAGE.EXIT);
	}
	
	/// start vibe working loop
	void run()
	{
		
		tid = toShared(thisTid);
		
		hadRun = true;
		
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
		loadConfig();
		
		database = new shared Database(logger, appConfig); //because config may change
		
		database.setupPool();
		
		setupSettings();
		
		setupRouter();
	}
	
	void runVibeLoop()
	{
		setup();
		
		listenHTTP(cast(HTTPServerSettings)settings, cast(URLRouter) router);
		
		logger.logInfo("Starting vibe loop");
		
		runEventLoop();
	}
	
	void startVibe()
	{
		spawn(&server.startVibe, this);
	}
	
	private void stopVibe()
	{
		logger.logInfo("Stopping vibe loop");
		
		getEventDriver().exitEventLoop();
	}
	
	private void setupSettings()
	{
		auto settings = toUnqual(settings);
		auto appConfig = toUnqual(appConfig);
		
		settings.port = appConfig.port;
			
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
			rpcReq = RpcRequest(req.json);
			
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
		
		}
		catch (RpcException ex)
		{
			RpcError error = RpcError(ex);
			
			RpcResponse rpcRes = RpcResponse(rpcReq.id, error);
			
			res.writeBody(rpcRes.toJson.toPrettyString, CONTENT_TYPE);
		}
		
	}
	
	private HTTPServerSettings settings;

	private URLRouter router;
	
	private AppConfig appConfig; //create with setup()
	
	private ILogger logger;
	
	private Tid tid;
	
	private Database database; //create with setup()
	
	static private bool hadRun;
}

