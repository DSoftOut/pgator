// Written in D programming language
/**
* Caching system
*
* Copyright: © 2014 DSoftOut
* License: Subject to the terms of the MIT license, as written in the included LICENSE file.
* Authors: Zaramzan <shamyan.roman@gmail.com>
*
*/
module server.cache;

import core.atomic;
import core.sync.rwmutex;

import std.concurrency;
import std.exception;
import std.digest.md;

import vibe.data.json;

import json_rpc.response;
import json_rpc.request;
import json_rpc.error;

import server.sql_json;

import util;

private enum MAX_CACHE_SIZE = 1024 * 1024 * 1024; //1 Gbyte

private alias RpcResponse[string] stash;

private alias stash[string] CacheType;

private __gshared ReadWriteMutex mutex;

private string getHash(in RpcRequest req)
{
	MD5 md5;

	md5.start();

	ubyte[] bin = cast(ubyte[]) req.method;

	md5.put(bin);

	foreach(str; req.params)
	{
		bin = cast(ubyte[]) str;
		md5.put(bin);
	}
	
	foreach(str; req.auth.byValue())
	{
		bin = cast(ubyte[]) str;
		md5.put(bin);
	}

	auto hash = md5.finish();

	return toHexString(hash).idup;
}

/**
* Represent caching system
*
* Authors: Zaramzan <shamyan.roman@gmail.com>
*/
shared class RequestCache
{	
	/**
	* Construct caching system
	*
	* Params:
	* 	table = describes methods and caching rules
	*/
	this(shared SqlJsonTable table)
	{
		this.table = table;
		
		mutex = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_READERS);
	}
	
	/**
	* Drop cache by request
	*/
	bool reset(RpcRequest req)
	{			
		synchronized (mutex.writer)
		{
			if (req.method in cache)
			{
				return cache[req.method].remove(req.getHash);
			}
		}
		
		return false;
	}
	
	/**
	* Drop all method cache
	*/
	bool reset(string method)
	{		
		synchronized (mutex.writer)
		{	
			return cache.remove(method);
		}
	}
	
	/**
	* Add cache by request
	*/
	void add(in RpcRequest req, shared RpcResponse res)
	{	
		synchronized (mutex.writer)
		{
			if (ifMaxSize) return;
			
			if ((req.method in cache) is null)
			{
				shared stash aa;
				
				aa[req.getHash] = res;
					
				cache[req.method] = aa;
			}
			else
			{
				cache[req.method][req.getHash] = res;
			}
		}
	}
	
	/**
	* Search cache by request in memory.
	*
	* Params:
	*	req = RPC request
	*	res = if cache found in memory, res will be assigned
	*
	* Returns:
	*	true, if found in memory, otherwise returns false
	*/
	bool get(in RpcRequest req, out RpcResponse res)
	{
		synchronized(mutex.reader)
		{	
			auto p1 = req.method in cache; 
			if (p1)
			{
				auto p2 = req.getHash in cache[req.method];
				
				if (p2)
				{
					res = cast(RpcResponse) cache[req.method][req.getHash];
			
					return true;
				}
			}
					
		}
		
		return false;
}
	
	private bool ifMaxSize()
	{
		return cache.sizeof > MAX_CACHE_SIZE;
	}
	 
	private CacheType cache;
	
	private SqlJsonTable table;
	
	private Tid tid;
	
}



version(unittest)
{
	shared RequestCache cache;
	
	void initCache()
	{
		cache = new shared RequestCache(table);
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
	initTable();
	
	initCache();
	
	initResponses();
	
	cache.add(normalReq, normalRes.toShared);
	
	cache.add(notificationReq, notificationRes.toShared);
	
	cache.add(methodNotFoundReq, mnfRes.toShared);
	
	cache.add(invalidParamsReq, invalidParasmRes.toShared);
	
	import std.concurrency;
	import core.thread;
	import core.time;
	
	enum count = 10;
	foreach(i; 0 .. count) spawn(&foo);
	foreach(i; 0 .. count) receiveOnly!int();
	Thread.sleep(10.dur!"msecs"); // wait to last thread die
}
