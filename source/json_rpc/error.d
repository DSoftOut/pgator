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
	mixin t_field!(RPC_ERROR_CODE, "code");
	
	mixin t_field!(string, "message");
	
	mixin t_field!(RpcErrorData, "data");
	
	this(in Bson bson)
	{
		try
		{
			foreach(string k, v; bson)
			{
				if (k == "code")
				{
					this.code = cast(RPC_ERROR_CODE)v.get!int;
				}
				else if( k == "message")
				{
					this.message = v.get!string;
				}
				else if (k == "data")
				{
					this.data = RpcErrorData(v);
				}
			}
			
			if(!this.isValid) throw new RpcInternalError();
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
	
	this (RPC_ERROR_CODE code, string message, RpcErrorData errorData)
	{
		this.data = errorData;
		
		this(code, message);
	}
	
	Json toJson()
	{
		Json ret = Json.emptyObject;
		
		ret.code = code;
		
		ret.message = message;
		
		if (f_data)
		{
			ret.data = data.toJson();
		}
		
		return ret;
	}
	
	bool isValid() @property
	{
		return f_code && f_message;
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


class RpcParseError: Exception
{	
	this(in string msg)
	{
		super(msg);
	}
	
	this()
	{
		super(RPC_ERROR_MSG[RPC_ERROR_CODE.PARSE_ERROR]);
	}
}

class RpcInvalidRequest: Exception
{	
	this(in string msg)
	{
		super(msg);
	}
	
	this()
	{
		super(RPC_ERROR_MSG[RPC_ERROR_CODE.INVALID_REQUEST]);
	}
}

class RpcMethodNotFound: Exception
{
	this(in string msg)
	{
		super(msg);
	}
	
	this()
	{
		super(RPC_ERROR_MSG[RPC_ERROR_CODE.METHOD_NOT_FOUND]);
	}
}

class RpcInvalidParams: Exception
{	
	this(in string msg)
	{
		super(msg);
	}
	
	this()
	{
		super(RPC_ERROR_MSG[RPC_ERROR_CODE.INVALID_PARAMS]);
	}
}

class RpcInternalError: Exception
{
	this(in string msg)
	{
		super(msg);
	}
	
	this()
	{
		super(RPC_ERROR_MSG[RPC_ERROR_CODE.INTERNAL_ERROR]);
	}
}

class RpcServerError: Exception
{
	this(in string msg)
	{
		super(msg);
	}
	
	this()
	{
		super(RPC_ERROR_MSG[RPC_ERROR_CODE.SERVER_ERROR]);
	}
}

package mixin template t_id()
{
	/// Used to determine original request id type
	enum ID_TYPE
	{
		NULL,
		
		STRING,
		
		INTEGER
	}
	
	mixin t_field!(ID_TYPE, "idType");
	
	private string m_id;
	private bool f_id;
	private void id(ulong i) @property
	{
		m_id = to!string(i);
		
		idType = ID_TYPE.INTEGER;
		
		f_id = true;
	}
	private void id(string str) @property
	{
		if (str is null)
		{
			m_id = "null";
			
			idType = ID_TYPE.NULL;			
		}
		else
		{
			m_id = str;
			
			idType = ID_TYPE.STRING;
		}
		
		f_id = true;
	}
	string id() @property
	{
		return m_id;
	}
	
	Json idJson()
	{
		final switch (idType)
		{
			case ID_TYPE.NULL:
				return Json(null);
				
			case ID_TYPE.INTEGER:
				return Json(to!int(id));
				
			case ID_TYPE.STRING:
				return Json(id);
				
		}
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