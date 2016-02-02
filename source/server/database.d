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

import pgator.db.pool;
import pgator.db.async.pool;    
import pgator.db.connection;
import pgator.db.pq.connection;
import pgator.db.pq.libpq;

import json_rpc.error;
import json_rpc.request;
import json_rpc.response;

import server.cache;
import server.config;
import server.sql_json;

import dlogg.log;
import util;


/**
* Represent database layer
*
* Authors:
*      Zaramzan <shamyan.roman@gmail.com>
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
        pool.loggingAllTransactions = appConfig.logSqlTransactions;
    }
    
    /// allocate shared cache
    void createCache()
    {
        cache = new shared RequestCache(table); 
    }
    
    /**
    * Loads main table from database
    *
    * Throws:
    *     on $(B ConnTimeoutException) tries to reconnect
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
            size_t expected;
            if (!entry.isValidParams(req.params, expected))
            {
                throw new RpcInvalidParams(text("Expected ", expected, " parameters, ",
                        "but got ", req.params.length, "!"));
            }
            if (!entry.isValidFilter(expected))
            {
                throw new RpcServerError(text("Json RPC table is invalid! result_filter should be empty or size "
                    "of sql_queries, expected ", expected, " but got ", entry.result_filter.length));
            }    
            if (!entry.isValidOneRowConstraint(expected))
            {
                throw new RpcServerError(text("Json RPC table is invalid! one_row_flags should be empty or size "
                        "of sql_querise, expected ", expected, " but got ", entry.one_row_flags.length));
            }
                        
            try
            {
                InputRange!(immutable Bson) extremeDirtyHuckRunInSeparateThreadPleaseRedoneThis(string[] queries, string[] params, uint[] arg_nums, string[string] vars, bool[] oneRowFlag)
                {
                    InputRange!(immutable Bson) irangeRes = null;
                    Throwable e = null;

                    static void thread(shared IConnectionPool pool, shared InputRange!(immutable Bson)* resPtr, shared Throwable* ePtr, immutable string[] queries, immutable string[] params, immutable uint[] arg_nums, immutable string[string] vars, immutable bool[] oneRowFlag) {
                        try {
                            string[] _queries = queries.dup;
                            string[] _params = params.dup;
                            uint[] _arg_nums = arg_nums.dup;
                            string[string] _vars = cast(string[string]) vars.dup;
                            bool[] _oneRowFlag = oneRowFlag.dup;

                            InputRange!(immutable Bson) res = pool.execTransaction(_queries, _params, _arg_nums, _vars, _oneRowFlag);
                            *resPtr = cast(shared)res;
                        } catch(Throwable th) {
                            *ePtr = cast(shared)th;
                        }
                    }

                    std.concurrency.spawn(
                            &thread,
                            pool,
                            cast(shared)&irangeRes,
                            cast(shared)&e,
                            queries.idup,
                            params.idup,
                            arg_nums.idup,
                            cast(immutable) vars.dup,
                            oneRowFlag.idup
                        );

                    while(irangeRes is null) {
                        if(e !is null) throw e;
                        yield();
                    }
                    return irangeRes;
                }


                InputRange!(immutable Bson) irange = null;

                irange = extremeDirtyHuckRunInSeparateThreadPleaseRedoneThis(
                        entry.sql_queries,
                        req.params,
                        entry.arg_nums,
                        (entry.set_username ? req.auth : null),
                        entry.one_row_flags
                    );

                Bson[] processResultFiltering(R)(R data)
                    if(isInputRange!R && is(ElementType!R == immutable Bson))
                {
                    auto builder = appender!(Bson[]);
                    if(entry.needResultFiltering)
                    {
                        foreach(i, ibson; data)
                        {
                            if(entry.result_filter[i])
                                builder.put(cast()ibson);
                        }
                    } 
                    else
                    {
                        foreach(i, ibson; data) builder.put(cast()ibson);
                    }
                    
                    return builder.data;
                }
                
                Bson[] processOneRowConstraints(R)(R data)
                    if(isInputRange!R && is(ElementType!R == Bson))
                {
                    Bson transformOneRow(Bson bson)
                    {
                        Bson[string] columns;
                        try columns = bson.get!(Bson[string]);
                        catch(Exception e) return bson;
                        
                        Bson[string] newColumns;
                        foreach(name, col; columns)
                        {
                            Bson[] row;
                            try row = col.get!(Bson[]);
                            catch(Exception e) return bson;
                            if(row.length != 1) return bson;
                            newColumns[name] = row[0];
                        }
                        
                        return Bson(newColumns);
                    }
                    
                    auto builder = appender!(Bson[]);
                    if(entry.needOneRowCheck)
                    {
                        foreach(i, bson; data)
                        {
                            if(entry.one_row_flags[i])
                            {
                                builder.put(transformOneRow(bson));
                            } else
                            {
                                builder.put(bson);
                            }
                        }
                        return builder.data;
                    } else
                    {
                        return data;
                    }
                }
                
                auto resultBody = processOneRowConstraints(processResultFiltering(irange));
                RpcResult result = RpcResult(Bson(resultBody));
                res = RpcResponse(req.id, result);
            }
            catch (QueryProcessingException e)
            {
                res = RpcResponse(req.id, RpcError(RPC_ERROR_CODE.SERVER_ERROR, e.errorDetails));
            }
            catch (Exception e)
            {
                throw new RpcServerError(e.msg);
            }
            
            if (table.need_cache(req.method))
            {
                shared RpcResponse cacheRes = res.toShared();
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
        Duration aliveCheckTime = dur!"msecs"(appConfig.aliveCheckTime);
        Duration reTime;
        
        if (appConfig.sqlReconnectTime > 0)
        {
            reTime = dur!"msecs"(appConfig.sqlReconnectTime);
        }
        else
        {
            reTime = timeout;
        }

        api = new shared PostgreSQL(logger);
        auto provider = new shared PQConnProvider(logger, api);
        
        pool = new shared AsyncPool(logger, provider, reTime, timeout, aliveCheckTime);
    }
    
    private
    {
        shared IPostgreSQL api;
        shared ILogger logger;
        shared IConnectionPool pool;
        
        SqlJsonTable table;
        RequestCache cache;
        immutable AppConfig appConfig;
    }
}
