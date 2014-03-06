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

class Application
{
	shared public:

	this(shared ILogger logger, Options options)
	{
		this.mLogger = logger;

		this.options = options;

		init();
	}

	~this()
	{
		localLogger.finalize();

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

	shared(ILogger) logger()
	{
	    return mLogger;
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
		AppConfig aConf;

		bool invalid;

		bool tryReadConfig(string path)
		{
			if (path is null) return false;

			try
			{
				aConf = AppConfig(path);

				logger.logInfo("Readed "~path);

				return true;
			}
			catch(InvalidConfig e)
			{
				logger.logError(e.msg);

				invalid = true;

				return true;
			}
			catch(Exception e)
			{
				return false;
			}
		}

		foreach (path; options.configPaths)
		{
			if (tryReadConfig(path))
			{
				if (invalid)
				{
					logger.logError("Invalid config");

					return false;
				}

				appConfig = toShared(aConf);

				return true;
			}
		}

		logger.logError("Can't read config");

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

		string vibelog = buildNormalizedPath(options.logDir, appConfig.vibelog);

		setLogFile(vibelog, LogLevel.info);
		setLogFile(vibelog, LogLevel.error);
		setLogFile(vibelog, LogLevel.warn);
	}

	void setupRouter()
	{
		auto del = cast(HTTPServerRequestDelegate) &handler;

		router.any("*", del);
	}

	void setupDatabase()
	{
		database = new shared Database(localLogger, appConfig);

		database.setupPool();
	}

	bool setupLocalLog()
	{
		scope(failure)
		{
			return false;
		}

		string localLogPath = buildNormalizedPath(options.logDir, appConfig.logname);

		localLogger = new shared CLogger(localLogPath);

		return true;
	}

	void configure()
	{	
		enforce(loadAppConfig, "Failed to use config");

		enforce(setupLocalLog, "Can't create log");

		setupDatabase();

		try
		{
			database.loadJsonSqlTable();
		}
		catch(Throwable e)
		{
			localLogger.logError("Server error: "~e.msg);

			internalError = true;
		}

		database.createCache();

		setupSettings();

		setupRouter();
	}

	void startServer()
	{
		try
		{	
			configure();

			listenHTTP(settings, router);

			lowerPrivileges();

			logger.logInfo("Starting event loop");

			running = true;

			runEventLoop();
		}
		catch(Throwable e)
		{
			logger.logError("Server error: "~e.msg);

			finalize();
		}
	}

	void stopServer()
	{
		logger.logInfo("Stopping event loop");

		database.finalizePool();
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

	shared ILogger mLogger, localLogger;

	AppConfig appConfig;

	Database database;

	int conns;

	bool running;

	bool internalError;

	__gshared private:

	Options options;

	HTTPServerSettings settings;

	URLRouter router;
}
