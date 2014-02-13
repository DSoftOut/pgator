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

import table;

private enum VERSION
{
	FULL, PART
}

/// Temp
private immutable VERSION ver = VERSION.PART;


class Cache
{
	private alias RpcResponse[RpcRequest] stash;
	 
	private stash[string] cache;
	
	private Table table;
	
	this(Table table)
	{
		this.table = table;
	}
	
	bool reset(RpcRequest req)
	{
		if (!table.mayDrop(req.method))
		{
			return false;
		}
		
		static if (ver == VERSION.FULL)
		{
			return cache.remove(req.method);
		}
		else
		{
			return cache[req.method].remove(req);
		}
	}
	
	bool reset(string method)
	{
		if (!table.mayDrop(method))
		{
			return false;
		}
		
		return cache.remove(method);
	}
	
	void add(RpcRequest req, RpcResponse res)
	{
		cache[req.method][req] = res;
	}
	
}

static this()
{
	string[string] map;
	
	map["1"] = "string1";
	
	map["2"] = "bla";
	
	struct S
	{
		double foo;
	}
	
	S s; 
	
	S[string] map2;
	
	std.stdio.writeln(map.get("2", null));
	std.stdio.writeln(map2.get("2", S()));
	
}