// Written in D programming language
/**
* Caching system
*
*
* Authors: Zaramzan <shamyan.roman@gmail.com>
*
*/
module cache;

import core.atomic;
import core.sync.rwmutex;

import std.concurrency;
import std.exception;

import vibe.utils.hashmap;

import json_rpc.response;
import json_rpc.request;
import json_rpc.error;

import sql_json;

import util;

private enum VERSION
{
	/// Drop all cache by method
	FULL, 
	
	/// Drop only cache by uniq request
	REQUEST
}

/// CHOOSE ME
private immutable VER = VERSION.REQUEST;

private alias RpcResponse[RpcRequest] stash;

private alias stash[string] CacheType;

private __gshared ReadWriteMutex mutex;

shared class Cache
{	
	this(shared SqlJsonTable table)
	{
		this.table = table;
		
		mutex = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_READERS);
	}
	
	bool reset(RpcRequest req)
	{
		if (!table.needDrop(req.method))
		{
			return false;
		}
		
		static if (VER == VERSION.FULL)
		{
			synchronized (mutex.writer)
			{
				return cache.remove(req.method);
			}
		}
		else synchronized (mutex.writer)
		{
			return cache[req.method].remove(req);
		}
	}
	
	bool reset(string method)
	{
		if (!table.needDrop(method))
		{
			return false;
		}
		
		synchronized (mutex.writer)
		{	
			return cache.remove(method);
		}
	}
	
	void add(RpcRequest req, shared RpcResponse res)
	{	
		synchronized (mutex.writer)
		{
			if ((req.method in cache) is null)
			{
				shared stash aa;
				
				aa[req] = res;
					
				cache[req.method] = aa;
			}
			else
			{
				cache[req.method][req] = res;
			}
		}
	}
	
	bool get(RpcRequest req, out RpcResponse res)
	{
		scope(failure)
		{
			return false;
		}
		
		synchronized(mutex.reader)
		{	
			res = cast(RpcResponse) cache[req.method][req];
			
			res.id = req.id;
			
			return true; 
		}
	}
	 
	private CacheType cache;
	
	private SqlJsonTable table;
	
	private Tid tid;
	
}



version(unittest)
{
	shared Cache cache;
	
	void initCache()
	{
		cache = new shared Cache(table);
	}
	
	//get
	void get()
	{
		import std.stdio;
		RpcResponse res;
		
		//writeln("into get");
		if (cache.get(normalReq, res))
		{
			//writeln(res.toJson);
		}
		
		if (cache.get(notificationReq, res))
		{
			//writeln(res.toJson);
		}
		
		if (cache.get(methodNotFoundReq, res))
		{
			//writeln(res.toJson);
		}
		
		if (cache.get(invalidParamsReq, res))
		{
			//writeln(res.toJson);
		}
	}
	
	// get -> reset -> get
	void foo()
	{
		scope(failure)
		{
			assert(false, "foo exception");
		}
		
		get();
		
		//std.stdio.writeln("Reseting cache");
		
		cache.reset(normalReq);
		
		cache.reset(notificationReq);
		
		cache.reset(methodNotFoundReq);
		
		cache.reset(invalidParamsReq);
		
		//std.stdio.writeln("Trying to get");
		
		get();
		
		import std.concurrency;
		send(ownerTid, 1);
	}
}

unittest
{	
	scope(failure)
	{
		assert(false, "Caching system unittest failed");
	}
	
	initTable();
	
	initCache();
	
	initResponses();
	
	cache.add(normalReq, normalRes.toShared);
	
	cache.add(notificationReq, notificationRes.toShared);
	
	cache.add(methodNotFoundReq, mnfRes.toShared);
	
	cache.add(invalidParamsReq, invalidParasmRes.toShared);
	
	import std.concurrency;
	
	Tid tid;
	
	for(int i = 0; i < 10; i++)
	{
		tid = spawn(&foo);
	}
	
	receiveOnly!int();
	
	std.stdio.writeln("Caching system test finished");
		
}
