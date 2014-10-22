// Written in D programming language
/**
* JSON-RPC 2.0 Protocol<br>
* 
* $(B This module contain JSON-RPC 2.0 response)
*
* See_Also:
*    $(LINK http://www.jsonrpc.org/specification)
*
* Copyright: © 2014 DSoftOut
* License: Subject to the terms of the MIT license, as written in the included LICENSE file.
* Authors: Zaramzan <shamyan.roman@gmail.com>
*
*/
module json_rpc.response;

import vibe.data.json;
import vibe.data.bson;

import util;

import json_rpc.error;

/**
* Struct desctibes JSON-RPC 2.0 response
*
* Example
* ------
*  auto res1 = RpcResponse(1, error);
*  auto res2 = RpcResponse(Json(null), result);
*  aut0 res3 = RpcResponse("mycustomidsystem", result);
* ------
* 
* Authors: Zaramzan <shamyan.roman@gmail.com>
*/
struct RpcResponse
{	
	private string jsonrpc = RPC_VERSION;
	
	mixin t_field!(RpcResult, "result");
	
	mixin t_field!(RpcError, "error");
	
	Json id = Json(null);
	
	this(Json id)
	{		
		this.id = id;
	}
	
	this(Json id, RpcError error)
	{
		this(id);
		
		this.error = error;
	}
	
	this(Json id, RpcResult result)
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
		
		ret.id = id;
		
		return ret;
	}
	
	bool isValid() @property
	{
		return f_result || f_error;
	}
	
	shared void opAssign(shared RpcResponse res)
	{
		this = res;
	}
	
	shared(RpcResponse) toShared()
	{
		auto res = this;
		
		return cast(shared RpcResponse) res;
	}
}


/**
* Struct describes JSON-RPC 2.0 result which used in RpcRequest
*
* Example
* ------
*  auto res = RpcResult(res);
* ------ 
* 
* Authors: Zaramzan <shamyan.roman@gmail.com>
*/
struct RpcResult
{
	mixin t_field!(Bson, "bson");
	
	///Supported only ctor from $(B Bson) yet
	this(in Bson bson)
	{
		this.bson = bson;
	}
	
	Json toJson() @property
	{
		if (f_bson)
		{
		    auto json = bson.toJson;
		    if(json.length == 1) return json[0];
			else return json;
		}
		
		return Json.emptyObject;
	}
}

version(unittest)
{
	import vibe.data.bson;
	import vibe.data.json;
	
	__gshared RpcResponse normalRes;
	__gshared RpcResponse  notificationRes;
	__gshared RpcResponse mnfRes;
	__gshared RpcResponse  invalidParasmRes;
	
	void initResponses()
	{		
		normalRes = RpcResponse(Json(1), 
			RpcResult(Bson([Bson(19)])));

		notificationRes = RpcResponse(Json(null),
			RpcResult(Bson([Bson(966)])));
		
		mnfRes = RpcResponse(Json(null),
			RpcError(new RpcMethodNotFound()));
		
		invalidParasmRes = RpcResponse(Json(null),
			RpcError(new RpcInvalidParams()));
	
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
	
	auto id = Json(null);
	
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