// Written in D programming language
/**
* Contains database using logic
*
*
* Authors: Zaramzan <shamyan.roman@gmail.com>
*        , NCrashed <ncrashed@gmail.com>
*/
module database;

import core.time;
import core.thread;

import std.string;
import std.range;
import std.array;
import std.algorithm;

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
	    Bson[] convertRowEchelon(const Bson from)
	    {
	        auto m = from.deserializeBson!(Bson[][string]);
	        Bson[string][] result;
	        foreach(colName, colVals; m)
	        {
	            foreach(row, val; colVals)
	            {
	                if(result.length <= row)
	                {
	                    result ~= [colName:val];
	                }
	                else
	                {
	                    result[row][colName] = val;
                    }
                }
	        }
	        return result.map!(a => Bson(a)).array;
	    }
	    
		string queryStr = "SELECT * FROM "~appConfig.sqlJsonTable;
		
		shared SqlJsonTable sqlTable = new shared SqlJsonTable();
		
		void load()
		{
			auto arri = pool.execTransaction([queryStr]);
			
			foreach(ibson; arri)
			{			
				foreach(v; convertRowEchelon(ibson))
				{
					sqlTable.add(deserializeFromJson!Entry(v.toJson));
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
						
			logger.logInfo("Querying pool");
			
			try
			{			
				auto irange = pool.execTransaction(entry.sql_queries, req.params, req.auth);
				
				auto builder = appender!(Bson[]);
				foreach(ibson; irange)
				{
				    builder.put(Bson.fromJson(ibson.toJson));
				}
				
				RpcResult result = RpcResult(Bson(builder.data));
				res = RpcResponse(req.id, result);
			}
			catch (QueryProcessingException e)
			{
				res = RpcResponse(req.id, RpcError(RPC_ERROR_CODE.SERVER_ERROR, e.msg));
			}
			catch (Exception e)
			{
				throw new RpcServerError(e.msg);
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
			logger.logInfo("Reseting method: "~meth);
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
		Duration timeout = dur!"msecs"(appConfig.sqlTimeout);
		
		Duration reTime;
		
		if (appConfig.sqlReconnectTime > 0)
		{
			reTime = dur!"msecs"(appConfig.sqlReconnectTime);
		}
		else
		{
			reTime = timeout;
		}

		auto provider = new shared PQConnProvider(logger, new PostgreSQL);
		
		pool = new shared AsyncPool(logger, provider, reTime, timeout);
	}
	
	IConnectionPool pool;
	
	SqlJsonTable table;
	
	Cache cache;
	
	AppConfig appConfig;
	
	ILogger logger;
}