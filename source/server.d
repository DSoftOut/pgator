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

import vibe.http.server;
import vibe.http.router;
import vibe.core.driver;
import vibe.core.core;

import json_rpc.request;
import json_rpc.error;
import json_rpc.response;

import config;

enum MESSAGE
{
	START,
	
	STOP,
	
	RESTART,
	
	EXIT
}

version(unittest)
{
	//nothing
}
else
{	
	static ~this()
	{
		send(tid, MESSAGE.EXIT);
	}
}


/// setups settings and router
private void setup()
{
	settings = cast(shared HTTPServerSettings) new HTTPServerSettings();
	
	router = cast(shared URLRouter) new URLRouter();
	
	appConfig = cast(shared AppConfig) AppConfig(CONFIG_PATH);
	
	setupSettings();
	
	setupRouter();
}

/// start vibe working loop
void run()
{
	tid = thisTid;
	
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

private void runVibeLoop()
{
	setup();
	listenHTTP(cast(HTTPServerSettings)settings, cast(URLRouter) router);
	runEventLoop();
}

private void startVibe()
{
	spawn(&runVibeLoop);
}

private void stopVibe()
{
	std.stdio.writeln("stopVibe");
	getEventDriver().exitEventLoop();
}

private void setupSettings()
{
	auto settings = cast(HTTPServerSettings) server.settings;
	auto appConfig = cast(AppConfig) server.appConfig;
	
	settings.port = appConfig.port;
		
	if (appConfig.hostname) 
		settings.hostName = appConfig.hostname;
		
	if (appConfig.bindAddresses)
		settings.bindAddresses = appConfig.bindAddresses;
}

private void setupRouter()
{	
	auto router = cast(URLRouter) server.router;
	
	router.any("*", &handler);
	
}

//Заглушка
private bool ifMaxConn() @property
{
	return false;
}

//Заглушка
private RpcResult query(in RpcRequest req)
{
	return RpcResult();
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
		
		if (hasAuth(req, user, password))
		{
			string[string] map;
			
			rpcReq.auth = map;
			
			enforceEx!RpcInvalidRequest(appConfig.sqlAuth.length >=2, "sqlAuth must have at least 2 elements");
			
			rpcReq.auth[appConfig.sqlAuth[0]] = user;
			
			rpcReq.auth[appConfig.sqlAuth[1]] = password;
		}
		
		auto result = query(rpcReq);
		
		auto rpcRes = RpcResponse(rpcReq.id, result);
		
		res.writeBody(rpcRes.toJson.toPrettyString, CONTENT_TYPE);
	
	}
	catch (RpcException ex)
	{
		RpcError error = RpcError(ex);
		
		RpcResponse rpcRes = RpcResponse(rpcReq.id, error);
		
		res.writeBody(rpcRes.toJson.toPrettyString, CONTENT_TYPE);
	}
	
}

private shared HTTPServerSettings settings;

private shared URLRouter router;

private shared AppConfig appConfig;

private __gshared Tid tid;

