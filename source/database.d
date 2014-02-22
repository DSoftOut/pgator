// Written in D programming language
/**
* Contains database using logic
*
*
* Authors: Zaramzan <shamyan.roman@gmail.com>
*          NCrashed <ncrashed@gmail.com>
*/
module database;

import core.time;

import std.string;

import vibe.data.bson;

import db.pool;
import db.asyncPool;
import db.connection;
import db.pq.connection;
import db.pq.libpq;

import json_rpc.error;
import json_rpc.request;
import json_rpc.response;

import cache;
import config;
import log;
import sql_json;
import util;


shared class Database
{
	
	this(shared ILogger logger, shared AppConfig appConfig)
	{
		this.logger = logger;
		
		this.appConfig = appConfig;
		
		init();
	}
	
	~this()
	{
		pool.finalize((){});
	}
	
	private void init()
	{
		Duration reTime = dur!"msecs"(appConfig.sqlTimeout);
		
		Duration freeTime;
		
		if (appConfig.sqlReconnectTime > 0)
		{
			freeTime = dur!"msecs"(appConfig.sqlReconnectTime);
		}
		else
		{
			freeTime = reTime;
		}
		
		try
		{
			auto provider = new shared PQConnProvider(logger, new PostgreSQL);
			
			pool = new shared AsyncPool(logger, provider, reTime, freeTime);
		}
		catch(Throwable ex)
		{
			logger.logError(format("%s:%s(%d)", ex.msg, ex.file, ex.line));
			
			throw ex;
		} 
	}
	
	void setupPool()
	{
		pool.finalize((){}); //todo
		
		foreach(server; appConfig.sqlServers)
		{
			pool.addServer(server.connString, server.maxConn);
			
			logger.logInfo("Connecting to" ~ server.name);
		}
		
		loadJsonSqlTable();
	}
	
	private void loadJsonSqlTable()
	{
		enum queryStr = "";
		
		try
		{
			auto frombd = pool.execQuery(queryStr, [appConfig.sqlJsonTable]);
			//todo...
		}
		catch(Exception ex)
		{
			logger.logError(format("%s:%s(%d)", ex.msg, ex.file, ex.line));
			throw ex;
		}
	}
	
	RpcResponse query(RpcRequest req)
	{	
		RpcResponse res;
		
		if (cache.get(req, res))
		{
			if (table.needDrop(req.method))
			{
				cache.reset(req);
			}
			
			return res;
		}
		
		Entry entry;
			
		if (!table.methodFound(req.method, entry))
		{
			throw new RpcMethodNotFound();
		}
		else
		{
			if (!entry.isValidParams(req.params))
			{
				throw new RpcInvalidParams();
			}
			
			if (entry.set_username && req.auth is null)
			{
				throw new RpcServerError("Authorization required");
			}
			
			auto frombd = tryEx!RpcServerError(pool.execQuery(entry.sql_query, req.params));
			
			Bson[] arr = new Bson[0];
			foreach(each; frombd)
			{
				if (each.resultStatus != ExecStatusType.PGRES_TUPLES_OK)
				{
					throw new RpcServerError(each.resultErrorMessage);
				}
				
				arr ~= each.asBson();
			}
			
			RpcResult result = RpcResult(Bson(arr));
			
			res = RpcResponse(req.id, result);
			
			//problem
			shared RpcResponse cacheRes = res.toShared();
			
			if (entry.need_cache)
			{
				cache.add(req, cacheRes);
			}
			else if (table.needDrop(req.method))
			{
				cache.reset(req);
			}
		}
		
		return res;
	}
	
	private shared IConnectionPool pool;
	
	private SqlJsonTable table;
	
	private Cache cache;
	
	private AppConfig appConfig;
	
	private shared ILogger logger;
}