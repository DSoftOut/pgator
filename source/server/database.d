// Written in D programming language
/**
* Contains database using logic
*
* Copyright: © 2014 DSoftOut
* License: Subject to the terms of the MIT license, as written in the included LICENSE file.
* Authors: Zaramzan <shamyan.roman@gmail.com>
*/
module server.database;

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

import server.cache;
import server.config;
import server.sql_json;

import log;
import util;


/**
* Represent database layer
*
* Authors:
*	  Zaramzan <shamyan.roman@gmail.com>
*/
shared class Database
{
    /**
    *   Construct object from ILogger and configuration file.   
    */
	this(shared ILogger logger, immutable AppConfig appConfig)
	{
		this.logger = logger;
		
		this.appConfig = appConfig;
		
		init();
	}
	
	/// configures async pool
	void setupPool() // called on every start / restart
	{		
		foreach(server; appConfig.sqlServers)
		{
		    logger.logInfo(text("Connecting to ", server.name, ". Adding ", server.maxConn, " connections."));
			pool.addServer(server.connString, server.maxConn);	
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
			table.makeDropMap();

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
	
	
	/// finalize database resources
	/**
	*  TODO: docs here
	*/
	void finalize()
	{
	    if(pool !is null)
	        pool.finalize();
        if(api !is null)
            api.finalize();
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
			logger.logDebug("Found in cache");
			
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
						
			logger.logDebug("Querying pool");
			
			try
			{			
				InputRange!(immutable Bson) irange;
				
				if (entry.set_username)
				{
					irange = pool.execTransaction(entry.sql_queries, req.params, req.auth);
				}
				else
				{
					irange = pool.execTransaction(entry.sql_queries, req.params);
				}
				
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
				res = RpcResponse(req.id, RpcError(RPC_ERROR_CODE.SERVER_ERROR, "Server error. " ~ e.msg));
			}
			catch (Exception e)
			{
				throw new RpcServerError(e.msg);
			}

			shared RpcResponse cacheRes = res.toShared();
			
			if (table.need_cache(req.method))
			{
				logger.logDebug("Adding to cache");
				cache.add(req, cacheRes);
			}
		}
		
		return res;
	}
	
	/**
	* Returns: true, if authorization required in json_rpc
	*/
	bool needAuth(string method)
	{
		return table.needAuth(method);
	}
	
	/**
	* Drop caches if needed
	*/
	void dropcaches(string method)
	{
		foreach(meth; table.needDrop(method))
		{
			logger.logDebug("Reseting method: "~meth);
			cache.reset(meth);
		}
	}
	
	/**
	* Initializes database resources
	*
	*/
	private void init() //called once
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

		api = new shared PostgreSQL();
		auto provider = new shared PQConnProvider(logger, api);
		
		pool = new shared AsyncPool(logger, provider, reTime, timeout);
	}
	
	private
	{
	    shared IPostgreSQL api;
	    shared ILogger logger;
    	shared IConnectionPool pool;
    	
    	SqlJsonTable table;
    	Cache cache;
    	immutable AppConfig appConfig;
	}
}
