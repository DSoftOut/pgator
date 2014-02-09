// Written in D programming language
/**
* JSON-RPC 2.0 Protocol<br>
* 
* $(B This module contain JSON-RPC 2.0 request)
*
* See_Also:
*    $(LINK http://www.jsonrpc.org/specification)
*
* Authors: Zaramzan <shamyan.roman@gmail.com>
*
*/

module json_rpc.request;

import std.exception;

import vibe.data.json;

import util;

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

class RpcInvalidRequest : Exception
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

private mixin template t_id()
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
/**
* structure describes JSON-RPC 2.0 request
*
* Example
* ------
* auto req = RpcRequest(jsonStr);
* writefln("id=%s method=%s params:%s", req.id, req.method, req.params); //these methods are read-only
* writefln("id type:", req.idType);
* ------
* 
*/
struct RpcRequest
{
	
	mixin t_field!(string, "jsonrpc");
	
	mixin t_field!(string, "method");
	
	mixin t_field!(string[], "params");
	
	mixin t_id;
	
	this(in string jsonStr)
	{
		Json json;
		try
		{
			json = parseJsonString(jsonStr);
		}
		catch(Exception ex)
		{
			throw new RpcParseError(ex.msg);
		}
		
		this(json);
	}
	
	this(in Json json)
	{
		if (json.type != Json.Type.object)
		{
			throw new RpcInvalidRequest();
		}
		
		foreach(string k, v; json)
		{
			
			//delegate
			void set(T, alias var)(bool thr = true)
			{
				Json.Type type;
				T var1;
				
				static if (is(T : string))
				{
					type = Json.Type.string;
					var1 = v.to!T;
				}
				else static if (is(T : int))
				{
					type = Json.Type.int_;
					var1 = v.to!T;
				}
				else static if (is(T == string[]))
				{
					type = Json.Type.array;
											
					var1 = new string[0];
					foreach(json; v)
					{	
						if ((json.type == Json.Type.object)||(json.type == Json.Type.object))
						{
							throw new RpcInvalidRequest("Supported only plain data in request");
						}
						var1 ~= json.to!string();
					}
				}
				else
				{
					static assert(true, "unsupported type "~T.stringof);
				}
				
				if ((v.type != type)&&(thr))
				{
					throw new RpcInvalidRequest();
				}
				
				var = var1;
				
			}
			//////////////////////////////
			
			
			if (k == "jsonrpc")
			{
				set!(string, jsonrpc);
			}
			else if (k == "method")
			{
				set!(string, method);
			}
			else if (k == "params")
			{
				set!(string[], params);
			}
			else if (k == "id")
			{				
				if (v.type == Json.Type.int_)
				{
					id = v.to!ulong;
				}
				else if (v.type == Json.Type.string)
				{
					id = v.to!string;
				}
				else if (v.type == Json.Type.null_)
				{
					id = null;
				}
				else
				{
					throw new RpcInvalidRequest("Invalid id");
				}
			}
		}
		
		if (!isValid)
		{
			throw new RpcInvalidRequest();
		}
		
		
	}
	
	private bool isComplete() @property
	{
		return f_jsonrpc && f_method;
	}
	
	private bool isJsonRpc2() @property
	{
		return jsonrpc == "2.0";
	}
	
	private bool isValid() @property
	{
		return isJsonRpc2 && isComplete;
	}
	
	version(unittest)
	{
		
		bool compare(RpcRequest s2)
		{
			if (this.id == s2.id)
			{
				if (this.method == s2.method)
				{
					if (this.jsonrpc == s2.jsonrpc)
					{
						if (this.params.length == s2.params.length)
						{
							for(int i = 0; i < s2.params.length; i++)
							{
								if( this.params[i] != s2.params[i])
								{
									return false;
								}
							}
							
							return true;
						}
					}
				}
			}
			
			return false;
		}
		
		this(string jsonrpc, string method, string[] params, string id)
		{
			this.jsonrpc = jsonrpc;
			this.method = method;
			this.params = params;
			this.id = id;
		}
	}	
}

version(unittest)
{
	string example1 = 
		"{\"jsonrpc\": \"2.0\", \"method\": \"subtract\", \"params\": [42, 23], \"id\": 1}";
		
	string example2 = 
		"{\"jsonrpc\": \"2.0\", \"method\": \"subtract\", \"params\": {\"subtrahend\": 23, \"minuend\": 42}, \"id\": 3}";
		
	string example3 = 
		"{\"jsonrpc\": \"2.0\", \"method\": \"update\", \"params\": [1,2,3,4,5]}";
	
	string example4 = 
		"{\"jsonrpc\": \"2.0\", \"method\": \"foobar\"}";
		
	string example5 =
		"{\"jsonrpc\": \"2.0\", \"method\": \"foobar, \"params\": \"bar\", \"baz]";
		
	string example6 = 
		"[]";
}

unittest
{
	//Testing normal rpc request
	auto req1 = RpcRequest("2.0", "substract", ["42", "23"], "1");
	assert(!RpcRequest(example1).compare(req1), "RpcRequest test failed");
	
	//Testing RpcInvalidRequest("Supported only plain data")
	try
	{
		auto req2 = RpcRequest(example2);
		assert(true, "RpcRequest test failed");
	}
	catch(RpcInvalidRequest ex)
	{
		//nothing
	}
	
	
	//Testing rpc notification with params
	auto req3 = RpcRequest("2.0", "update", ["1", "2", "3", "4", "5"], null);
	assert(!RpcRequest(example3).compare(req3), "RpcRequest test failed");
	
	//Testing rpc notification w/o params
	auto req4 = RpcRequest("2.0", "foobar", new string[0], null);
	assert(!RpcRequest(example4).compare(req4), "RpcRequest test failed");
	
	//Testing invalid json
	try
	{
		auto req5 = RpcRequest(example5);
		assert(true, "RpcRequest test failed");
	}
	catch(RpcInvalidRequest ex)
	{
		//nothiing
	}
	
	//Testing empty json array
	try
	{
		auto req6 = RpcRequest(example6);
		assert(true, "RpcRequest test failed");
	}
	catch(RpcInvalidRequest ex)
	{
		//nothing
	}
	
	
}
