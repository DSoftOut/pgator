// Written in D programming language
/**
* Caching system
*
*
* Authors: Zaramzan <shamyan.roman@gmail.com>
*
*/
module cache;


import std.digest.md;

import json_rpc.response;
import json_rpc.request;
import json_rpc.error;

import sql_json;

private enum VERSION
{
	/// Drop all cache by method
	FULL, 
	
	/// Drop only cache by uniq request
	REQUEST
}

/// CHOOSE ME
private immutable VER = VERSION.REQUEST;


class Cache
{
	private alias RpcResponse[RpcRequest] stash;
	 
	private stash[string] cache;
	
	private SqlJsonTable table;
	
	this(SqlJsonTable table)
	{
		this.table = table;
	}
	
	bool reset(ref RpcRequest req)
	{
		if (!table.needDrop(req.method))
		{
			return false;
		}
		
		static if (VER == VERSION.FULL)
		{
			synchronized (this) 
			{
				return cache.remove(req.method);
			}
		}
		else
		{
			synchronized (this)
			{
				return cache[req.method].remove(req);
			}
		}
	}
	
	bool reset(string method)
	{
		if (!table.needDrop(method))
		{
			return false;
		}
		
		synchronized (this) 
		{
			return cache.remove(method);
		}
	}
	
	void add(RpcRequest req, RpcResponse res)
	{	
		if ((req.method in cache) is null)
		{
			stash aa;
			aa[req] = res;
			
			synchronized(this)
				cache[req.method] = aa;
		}
		else synchronized (this) 
		{
			cache[req.method][req] = res;
		}
		
	}
	
	bool get(ref RpcRequest req, out RpcResponse res)
	{
		scope(failure)
		{
			return false;
		}
		
		res = cache[req.method][req];
		
		return true; 
	}
	
}

private __gshared Cache p_cache;

Cache cache() @property
{
	return p_cache;
}


version(unittest)
{
	void initCache()
	{
		p_cache = new Cache(table);
	}
	
	//get
	void get()
	{
		//import std.stdio;
		RpcResponse res;
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
	initTable();
	initCache();
	initResponses();
	
	cache.add(normalReq, normalRes);
	cache.add(notificationReq, notificationRes);
	cache.add(methodNotFoundReq, mnfRes);
	cache.add(invalidParamsReq, invalidParasmRes);
	
	import std.concurrency;
	
	Tid tid;
	
	for(int i = 0; i < 10; i++)
	{
		tid = spawn(&foo);
	}
	
	receiveOnly!int();
	
	std.stdio.writeln("Caching system test finished");
		
}
