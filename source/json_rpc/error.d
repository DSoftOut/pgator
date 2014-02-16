// Written in D programming language
/**
* JSON-RPC 2.0 Protocol<br>
* 
* $(B This module contain JSON-RPC 2.0 errors)
*
* See_Also:
*    $(LINK http://www.jsonrpc.org/specification)
*
* Authors: Zaramzan <shamyan.roman@gmail.com>
*
*/
module json_rpc.error;

import vibe.data.bson;

import util;

/// contains JSON-RPC 2.0 error codes
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

enum RPC_VERSION = "2.0";

immutable string[RPC_ERROR_CODE] RPC_ERROR_MSG; 
	
static this()
{
	RPC_ERROR_MSG[RPC_ERROR_CODE.PARSE_ERROR] = "Parse error";
	
	RPC_ERROR_MSG[RPC_ERROR_CODE.INVALID_REQUEST] = "Invalid request";
	
	RPC_ERROR_MSG[RPC_ERROR_CODE.METHOD_NOT_FOUND] = "Method not found",
	
	RPC_ERROR_MSG[RPC_ERROR_CODE.INVALID_PARAMS] = "Invalid params";
	
	RPC_ERROR_MSG[RPC_ERROR_CODE.INTERNAL_ERROR] = "Internal error";
	
	RPC_ERROR_MSG[RPC_ERROR_CODE.SERVER_ERROR] = "Server error";
	
	RPC_ERROR_MSG.rehash();	
}


/**
* Struct describes JSON-RPC 2.0 error object which used in RpcRequest
*
* Example
* ------
*  auto err1 = RpcError(bson);
*  auto err2 = RpcError(RPC_ERROR_CODE.INVALID_PARAMS, RPC_ERROR_MSG[RPC_ERROR_CODE.INVALID_PARAMS]);
*  auto err3 = RpcError(RPC_ERROR_CODE.INVALID_PARAMS, "mycustommessage");
*  auto err4 = RRpcError(RPC_ERROR_CODE.INVALID_PARAMS, RPC_ERROR_MSG[RPC_ERROR_CODE.INVALID_PARAMS], erroData); 
*
*  //toJson
*  err2.toJson(); 
* ------ 
*/
struct RpcError
{
	@required
	string message;
	
	@required
	int code;
	
	@possible
	Json data = Json(null);
	
	this(in Bson bson)
	{
		try
		{
			this = deserializeFromJson!RpcError(bson.toJson);
		}
		
		catch(Exception ex)
		{
			throw new RpcInternalError(ex.msg);
		}
	}
	
	this(RPC_ERROR_CODE code, string message)
	{
		this.code = code;
		this.message = message;
	}
	
	this (RPC_ERROR_CODE code, string message, Json errorData)
	{
		this.data = errorData;
		
		this(code, message);
	}
	
	this(RpcErrorEx ex)
	{
		this(ex.code, ex.message);
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

/**
* Struct describes JSON-RPC 2.0 error.data
*
* Example
* ------
*  auto data = RpcErrorData(bson); //supported only ctor from bson yet
*  
*  //to Json
*  data.toJson();
* ------
*/
@disable
struct RpcErrorData 
{
	mixin t_field!(Json, "json");
	
	this(in Bson bson)
	{
		try
		{
			this.json = bson.toJson();
		}
		catch (Exception ex)
		{
			throw new RpcInternalError();
		}
	}
	
	Json toJson()
	{
		if (f_json)
		{
			return json;
		}
		return Json.emptyObject;
	}
}

interface RpcErrorEx
{
	RPC_ERROR_CODE code() @property;
	
	string message() @property;
}

class RpcParseError: Exception, RpcErrorEx
{	
	this(in string msg)
	{
		super(msg);
	}
	
	this()
	{
		super(RPC_ERROR_MSG[code]);
	}
	
	RPC_ERROR_CODE code() @property
	{
		return RPC_ERROR_CODE.PARSE_ERROR;
	}
	
	string message() @property
	{
		return this.msg;
	}
}

class RpcInvalidRequest: Exception, RpcErrorEx
{	
	this(in string msg)
	{
		super(msg);
	}
	
	this()
	{
		super(RPC_ERROR_MSG[code]);
	}
	
	RPC_ERROR_CODE code() @property
	{
		return RPC_ERROR_CODE.INVALID_REQUEST;
	}
	
	string message() @property
	{
		return this.msg;
	}
}

class RpcMethodNotFound: Exception, RpcErrorEx
{
	this(in string msg)
	{
		super(msg);
	}
	
	this()
	{
		super(RPC_ERROR_MSG[code]);
	}
	
	RPC_ERROR_CODE code() @property
	{
		return RPC_ERROR_CODE.METHOD_NOT_FOUND;
	}
	
	string message() @property
	{
		return this.msg;
	}
}

class RpcInvalidParams: Exception, RpcErrorEx
{	
	this(in string msg)
	{
		super(msg);
	}
	
	this()
	{
		super(RPC_ERROR_MSG[code]);
	}
	
	RPC_ERROR_CODE code() @property
	{
		return RPC_ERROR_CODE.INVALID_PARAMS;
	}
	
	string message() @property
	{
		return this.msg;
	}
}

class RpcInternalError: Exception, RpcErrorEx
{
	this(in string msg)
	{
		super(msg);
	}
	
	this()
	{
		super(RPC_ERROR_MSG[code]);
	}
	
	RPC_ERROR_CODE code() @property
	{
		return RPC_ERROR_CODE.INTERNAL_ERROR;
	}
	
	string message() @property
	{
		return this.msg;
	}
}

class RpcServerError: Exception, RpcErrorEx
{
	this(in string msg)
	{
		super(msg);
	}
	
	this()
	{
		super(RPC_ERROR_MSG[code]);
	}
	
	RPC_ERROR_CODE code() @property
	{
		return RPC_ERROR_CODE.SERVER_ERROR;
	}
	
	string message() @property
	{
		return this.msg;
	}
}

package mixin template t_id()
{
	mixin t_field!(string, "sid");
	mixin t_field!(ulong, "uid");
	
	private void id(T)(T i) @property
	{
		static if (is(T : ulong))
		{
			uid = i;
		}
		else static if (is(T : string))
		{
			sid = i;
		}
		else static if (is( T == Json))
		{
			if (i.type == Json.Type.int_)
			{
				uid = i.to!ulong;
			}
			else if (i.type == Json.Type.null_)
			{
				sid = null;
			}
			else if (i.type == Json.Type.string)
			{
				sid = i.to!string;
			}
		}
		else
		{
			static assert(false, "Unsupported type id:"~T.stringof);
		}
	}
	
	string id() @property
	{
		if (f_uid)
		{
			return to!string(uid);
		}
		
		return sid;
	}
	
	Json idJson()
	{
		if (f_uid)
		{
			return Json(uid);
		}
		
		return Json(sid);
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