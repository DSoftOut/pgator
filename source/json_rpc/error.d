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

import util;

/// contains JSON-RPC 2.0 error codes
enum RPC_ERROR_CODE
{
	PARSE_ERROR = -32700,
	
	INVALID_REQUEST = -32600,
	
	METHOD_NOT_FOUND = -32601,
	
	INVALID_PARAMS = -32602,
	
	INTERNAL_ERROR = -32603,
	
	SERVER_ERROR = -32000,
	
	SERVER_ERROR_EXT = -32099
}

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

class RpcParseError:Exception
{

	this(in string msg)
	{
		super(msg);
	}
	
	this (RPC_ERROR_CODE code)
	{
		super(RPC_ERROR_MSG[code]);
	}
}

class RpcInvalidRequest:Exception
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

class RpcMethodNotFound:Exception
{
	this()
	{
		super(RPC_ERROR_MSG[RPC_ERROR_CODE.METHOD_NOT_FOUND]);
	}
}

class RpcInvalidParams:Exception
{
	this()
	{
		super(RPC_ERROR_MSG[RPC_ERROR_CODE.INVALID_PARAMS]);
	}
}

class RpcInternalError:Exception
{
	this()
	{
		super(RPC_ERROR_MSG[RPC_ERROR_CODE.INTERNAL_ERROR]);
	}
}

class RpcServerError:Exception
{
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
}