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
		pool.finalize((){ logger.logInfo("Pool finalized"); });
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
		foreach(server; appConfig.sqlServers)
		{
			pool.addServer(server.connString, server.maxConn);
			
			logger.logInfo("Connecting to " ~ server.name);
		}
		
		loadJsonSqlTable();
		
		createCache();
	}
	
	private void createCache()
	{
		cache = new shared Cache(table); 
	}
	
	void finalizePool(void delegate() del)
	{
		pool.finalize(del);
	}
	
	private void loadJsonSqlTable()
	{
		string queryStr = "SELECT * FROM "~appConfig.sqlJsonTable;
		
		shared SqlJsonTable sqlTable = new shared SqlJsonTable();
		
		try
		{
			auto frombd = pool.execQuery(queryStr, []);
			
			foreach(entry; frombd)
			{			
				if (entry.resultStatus != ExecStatusType.PGRES_TUPLES_OK)
				{
					throw new Exception(entry.resultErrorMessage);
				}
				
				auto arr = entry.asNatBson().to!(Bson[]);
				
				foreach(v; arr)
				{
					Entry ent = deserializeFromJson!Entry(v.toJson);
					
					std.stdio.writeln(ent);
					
					sqlTable.add(ent);
				}
			}
			
			table = sqlTable;
		}
		catch(Exception ex)
		{
			logger.logError(format("%s:%s(%d)", ex.msg, ex.file, ex.line));
			throw ex;
		}
	}
	
	RpcResponse query(ref RpcRequest req)
	{	
		RpcResponse res;
		
		logger.logInfo("Searching in cache");
		
		if (cache.get(req, res))
		{
			logger.logInfo("Found in cache");
			
			res.id = req.id;
			
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
			
			string queryStr; 
			
			if (entry.set_username && req.auth is null)
			{
				throw new RpcServerError("Authorization required");
			}
			else
			{
				queryStr = "BEGIN; ";
				
				foreach(key; req.auth.byKey())
				{
					queryStr ~= format("SET LOCAL %s = '%s'; ", key, req.auth[key]);
				}
				
				queryStr ~= entry.sql_query~ " COMMIT;";
			}
			
			logger.logInfo("Querying pool");
			
			auto frombd = tryEx!RpcServerError(pool.execQuery(queryStr, req.params));
			
			Bson[] arr = new Bson[0];
			
			RpcServerError error = null;
			
			foreach(each; frombd)
			{
				if (each.resultStatus != ExecStatusType.PGRES_TUPLES_OK)
				{
					error =  new RpcServerError(each.resultErrorMessage);
				}
				
				arr ~= each.asBson();
			}
			
			if (error is null)
			{
				RpcResult result = RpcResult(Bson(arr));
			
				res = RpcResponse(req.id, result);
			}
			else
			{
				res = RpcResponse(req.id, RpcError(error));
			}
			
			//problem
			shared RpcResponse cacheRes = res.toShared();
			
			if (table.need_cache(req.method))
			{
				logger.logInfo("Adding to cache");
				cache.add(req, cacheRes);
			}
			
			foreach(meth; table.needDrop(req.method))
			{
				logger.logInfo("Reseting method:"~req.method);
				cache.reset(meth);
			}
		}
		
		return res;
	}
	
	private IConnectionPool pool;
	
	private SqlJsonTable table;
	
	private Cache cache;
	
	private AppConfig appConfig;
	
	private ILogger logger;
}