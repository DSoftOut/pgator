// Written in D programming language
/**
* Contains database using logic
*
*
* Authors: Zaramzan <shamyan.roman@gmail.com>
*/
module database;

import core.time;
import core.thread;

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


/**
* Represent database layer
*
* Authors:
*	Zaramzan <shamyan.roman@gmail.com>	
*/
shared class Database
{
	
	this(shared ILogger logger, shared AppConfig appConfig)
	{
		this.logger = logger;
		
		this.appConfig = appConfig;
		
		init();
	}
	
	/// configures async pool
	// called on every start / restart
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
	
	/// finalize async db.pool
	void finalizePool()
	{
		pool.finalize();
	}
	
	/**
	* Queries parsed request from async pool <br>
	*
	* Also caches request if needed
	*/
	RpcResponse query(ref RpcRequest req)
	{	
		RpcResponse res;
		
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
//				queryStr = "BEGIN; ";
//				
//				foreach(key; req.auth.byKey())
//				{
//					queryStr ~= format("SET LOCAL %s = '%s'; ", key, req.auth[key]);
//				}
//				
//				queryStr ~= entry.sql_query~ " COMMIT;";
			
				queryStr = entry.sql_query;
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

			shared RpcResponse cacheRes = res.toShared();
			
			if (table.need_cache(req.method))
			{
				logger.logInfo("Adding to cache");
				cache.add(req, cacheRes);
			}
		}
		
		return res;
	}
	
	/**
	* Drop caches if needed
	*/
	void dropcaches(string method)
	{
		foreach(meth; table.needDrop(method))
		{
			logger.logInfo("Reseting method:"~method);
			cache.reset(meth);
		}
	}
	
	private:
	
	/**
	* Initializes database resources
	*
	*/
	//called once
	void init()
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

		auto provider = new shared PQConnProvider(logger, new PostgreSQL);
		
		pool = new shared AsyncPool(logger, provider, reTime, freeTime);
	}
	
	/// allocate shared cache
	void createCache()
	{
		cache = new shared Cache(table); 
	}
	
	/**
	* Loads main table from database
	*
	* Throws:
	* 	on $(B ConnTimeoutException) tries to reconnect
	*
	* Authors: 
	*	Zaramzan <shamyan.roman@gmail.com>
	* 	Ncrashed <ncrashed@gmail.com>
	*/
	void loadJsonSqlTable()
	{
		string queryStr = "SELECT * FROM "~appConfig.sqlJsonTable;
		
		shared SqlJsonTable sqlTable = new shared SqlJsonTable();
		
		void load()
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
					
					sqlTable.add(ent);
				}
			}
			
			table = sqlTable;
			
			logger.logInfo("Table loaded");
		}
		
		try
		{
			load();
		}
		catch(ConnTimeoutException ex)
		{
		    logger.logError("There is no free connections in the pool, retry over 1 sec...");
		    
		    Thread.sleep(1.seconds);
		    
		    load();
		}
	}
	
	IConnectionPool pool;
	
	SqlJsonTable table;
	
	Cache cache;
	
	AppConfig appConfig;
	
	ILogger logger;
}