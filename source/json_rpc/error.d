// Written in D programming language
/**
* JSON-RPC 2.0 Protocol<br>
* 
* $(B This module contain JSON-RPC 2.0 errors)
*
* See_Also:
*    $(LINK http://www.jsonrpc.org/specification)
*
* Copyright: © 2014 DSoftOut
* License: Subject to the terms of the MIT license, as written in the included LICENSE file.
* Authors: Zaramzan <shamyan.roman@gmail.com>
*/
module json_rpc.error;

import std.exception;

import vibe.data.bson;

import util;
import pgator.db.pq.api: PGQueryException;

/**
* Contains JSON-RPC 2.0 error codes
* 
* Authors: Zaramzan <shamyan.roman@gmail.com>
*/
enum RPC_ERROR_CODE:int
{
	NONE,
	
	PARSE_ERROR = -32700,
	
	INVALID_REQUEST = -32600,
	
	METHOD_NOT_FOUND = -32601,
	
	INVALID_PARAMS = -32602,
	
	INTERNAL_ERROR = -32603,
	
	SERVER_ERROR = -32000,
	
	SERVER_ERROR_EXT = -32099
}

/// Supported JSON-RPC protocol version
enum RPC_VERSION = "2.0";

/**
* Struct describes JSON-RPC 2.0 error object which used in RpcRequest
*
* Example
* ------
*  auto err1 = RpcError(bson);
*  auto err2 = RpcError(RPC_ERROR_CODE.INVALID_PARAMS, "Invalid params");
*  auto err3 = RpcError(RPC_ERROR_CODE.INVALID_PARAMS, "mycustommessage");
*  auto err4 = RpcError(RPC_ERROR_CODE.INVALID_PARAMS, "Invalid params", erroData); 
*  auto err5 = RpcError(new RpcInvalidParams());
*
*  //toJson
*  err2.toJson(); 
* ------ 
* 
* Authors: Zaramzan <shamyan.roman@gmail.com>
*/
struct RpcError
{
	@required
	string message;
	
	@required
	int code;
	
	@possible
	Json data = Json(null);
	
	PGQueryException.ErrorDetails errorDetails;

	this(in Bson bson)
	{
		this = tryEx!(RpcInternalError, deserializeFromJson!RpcError)(bson.toJson);
	}
	
	this(RPC_ERROR_CODE code, string message)
	{
		this.code = code;
		this.message = message;
	}
	
	this(RPC_ERROR_CODE code, PGQueryException.ErrorDetails ed)
	{
		this.code = code;
		this.message = ed.message;
		this.errorDetails = ed;
	}
	
	this (RPC_ERROR_CODE code, string message, Json errorData)
	{
		this.data = errorData;
		
		this(code, message);
	}
	
	this(RpcException ex)
	{
		this(ex.code, ex.msg);
	}
	
	Json toJson()
	{
		Json ret = Json.emptyObject;
		
		ret.code = code;
		
		ret.message = message;
		
		if (data.type != Json.Type.null_)
		{
			ret.data = data;
		}
		
		return ret;
	}
}


/// Super class for all JSON-RPC exceptions
class RpcException:Exception
{
	RPC_ERROR_CODE code;
	
	@safe pure nothrow this(string msg = "", string file = __FILE__, size_t line = __LINE__, Throwable next = null)
	{
		super(msg, file, line, next); 
	}

}

class RpcParseError: RpcException
{	
	@safe pure nothrow this(string msg = "", string file = __FILE__, size_t line = __LINE__)
	{
		code = RPC_ERROR_CODE.PARSE_ERROR;
		
		msg = "Parse error. " ~ msg;
		
		super(msg, file, line); 
	}
}

class RpcInvalidRequest: RpcException
{	
	@safe pure nothrow this(string msg = "", string file = __FILE__, size_t line = __LINE__)
	{
		code = RPC_ERROR_CODE.INVALID_REQUEST;
		
		msg = "Invalid request. " ~ msg;
		
		super(msg, file, line); 
	}
}

class RpcMethodNotFound: RpcException
{
	@safe pure nothrow this(string msg = "", string file = __FILE__, size_t line = __LINE__)
	{
		code = RPC_ERROR_CODE.METHOD_NOT_FOUND;
		
		msg = "Method not found. " ~ msg;
		
		super(msg, file, line);
	}
}

class RpcInvalidParams: RpcException
{	
	@safe pure nothrow this(string msg = "", string file = __FILE__, size_t line = __LINE__)
	{
		code = RPC_ERROR_CODE.INVALID_PARAMS;
		
		msg = "Invalid params. " ~ msg;
		
		super(msg, file, line); 
	}
}

class RpcInternalError: RpcException
{
	@safe pure nothrow this(string msg = "", string file = __FILE__, size_t line = __LINE__)
	{
		code = RPC_ERROR_CODE.INTERNAL_ERROR;
		
		msg = "Internal error. " ~ msg;
		
		super(msg, file, line);
	}
}

class RpcServerError: RpcException
{
	@safe pure nothrow this(string msg = "", string file = __FILE__, size_t line = __LINE__)
	{
		code = RPC_ERROR_CODE.SERVER_ERROR;
		
		msg = "Server error. " ~ msg;
		
		super(msg, file, line);
	}
}

unittest
{
	import vibe.data.bson;
	import vibe.data.json;
	
	auto code = cast(int) RPC_ERROR_CODE.METHOD_NOT_FOUND;
	auto message = "METHOD NOT FOUND";
	
	auto error1 = RpcError(Bson(["code":Bson(code),"message": Bson(message)])).toJson(); 
	
	auto error2 = RpcError(cast(RPC_ERROR_CODE)code, message).toJson();
	
	auto error = Json.emptyObject;
	error.code = code;
	error.message = message; 
	
	assert(error == error1, "RpcError unittest failed");
	assert(error == error2, "RpcError unittest failed");
}
