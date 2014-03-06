// Written in D programming language
/**
* Caching system
*
*
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

shared class Cache
{	
	this(shared SqlJsonTable table)
	{
		this.table = table;
		
		mutex = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_READERS);
	}
	
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
	
	bool reset(string method)
	{		
		synchronized (mutex.writer)
		{	
			return cache.remove(method);
		}
	}
	
	void add(in RpcRequest req, shared RpcResponse res)
	{	
		if (ifMaxSize) return;
		
		synchronized (mutex.writer)
		{
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
		synchronized(mutex.writer)
		{
			return cache.sizeof > MAX_CACHE_SIZE;
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
