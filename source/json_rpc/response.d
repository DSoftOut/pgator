// Written in D programming language
/**
* JSON-RPC 2.0 Protocol<br>
* 
* $(B This module contain JSON-RPC 2.0 response)
*
* See_Also:
*    $(LINK http://www.jsonrpc.org/specification)
*
* Authors: Zaramzan <shamyan.roman@gmail.com>
*
*/
module json_rpc.response;

import vibe.data.json;
import vibe.data.bson;

import util;

import json_rpc.error;


struct RpcResponse
{	
	private string jsonrpc = RPC_VERSION;
	
	mixin t_field!(RpcResult, "result");
	
	mixin t_field!(RpcError, "error");
	
	mixin t_id;
	
	
	this(T)(T id)
	{
		this.id = id;
	}
	
	this(T)(T id, ref RpcError error)
	{
		this(id);
		
		this.error = error;
	}
	
	this(T)(T id, ref RpcResult result)
	{
		this(id);
		
		this.result = result;
	}
	
	Json toJson()
	{
		if (!isValid)
		{
			throw new RpcInternalError();
		}
		
		Json ret = Json.emptyObject;
		
		ret.jsonrpc = jsonrpc;
		
		if (f_result)
		{
			ret.result = result.toJson();
		}
		else if (f_error)
		{
			ret.error = error.toJson();
		}
		
		ret.id = idJson();
		
		return ret;
	}
	
	bool isValid() @property
	{
		return f_id && (f_result || f_error);
	}
}

struct RpcResult
{
	mixin t_field!(Bson, "bson");
	
	this(in Bson bson)
	{
		this.bson = bson;
	}
	
	Json toJson() @property
	{
		if (f_bson)
		{
			return bson.toJson();
		}
		
		return Json.emptyObject;
	}
}


unittest
{
	import std.stdio;
	import vibe.data.bson;
	import vibe.data.json;
	
	//Testing normal response
	auto arr = new Bson[0];
	arr ~= Bson("1");
	arr ~= Bson(2);
	arr ~= Bson(null);
	
	auto result = RpcResult(Bson(arr));
	
	auto id = null;
	
	auto res1 = RpcResponse(id, result).toJson();
	
	auto res2 = Json.emptyObject;
	res2.id = id;
	res2.jsonrpc = RPC_VERSION;
	res2.result = result.toJson();
	
	assert(res1 == res2, "RpcResponse unittest failed");
	
	
	//Testing error response
	auto code = cast(int) RPC_ERROR_CODE.METHOD_NOT_FOUND;
	auto message = "METHOD NOT FOUND";
	
	auto error = RpcError(cast(RPC_ERROR_CODE)code, message);
	
	auto res3 = RpcResponse(id, error).toJson();
	
	auto res4 = Json.emptyObject;
	res4.id = id;
	res4.jsonrpc = RPC_VERSION;
	res4.error = error.toJson();
	
	assert(res3 == res4, "RpcResponse unittest failed");
}