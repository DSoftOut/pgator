
// Written in D programming language
/**
* Config reading system.
*
* Ctor $(B AppConfig(string)) create a config from file.
*
*
* Authors: Zaramzan <shamyan.roman@gmail.com>
*
*/
module config;

import std.exception;
import std.stdio;

import vibe.data.json;
import vibe.core.log;

import util;

enum CONFIG_PATH = "config.json";

struct AppConfig
{
	@required
	ushort port;
	
	@required
	uint maxConn;
	
	@required
	SqlConfig[] sqlServers;
	
	@required
	string sqlAuth;
	
	@required
	uint sqlTimeout;
	
	@required
	string sqlJsonTable;
	
	@possible
	string[] bindAddresses = null;
	
	@possible
	string hostname = null;
	
	@possible
	int sqlReconnectTime = -1;
	
	this(Json json)
	{
		try
		{
			this = deserializeFromJson!AppConfig(json);
		}
		catch (Exception ex)
		{
			throw new InvalidConfig(ex.msg);
		}
	}
	
	this(string path)
	{
		try
		{
			auto file = File(path, "r");
			
			string str;
			
			foreach(line; file.byLine)
			{
				str ~= line;
			}
			
			auto json = parseJson(str);
			
			this(json); 
		}
		catch (ErrnoException ex)
		{
			logError(ex.msg);
			throw new Exception("Config reading error");
		}
	}
}

struct SqlConfig
{
	@possible
	string name = null;
	
	@required
	uint maxConn;
	
	@required
	string connString;
}

class InvalidConfig:Exception
{
	this(in string msg)
	{
		super(msg);
	}
} 

version(unittest)
{
	string configExample = "
		{
	    \"bindAddresses\" : [
	            \"::\",
	            \"0.0.0.0\",
	    ],
	
	    \"hostname\" : \"\",
	
	    \"port\" : 8888,
	
	    \"maxConn\" : 50,
	
	    \"sqlServers\" : [
	        {
	            \"name\" : \"sql1\",
	            \"connString\" : \"\",
	            \"maxConn\" : 1
	        },
	        {
	            \"name\" : \"sql2\",
	            \"connString\" : \"\",
	            \"maxConn\" : 2
	        }
	    ],
	
	    \"sqlTimeout\": 100,
	
	    \"sqlReconnectTime\": 150,
	
	    \"sqlAuth\" : \"login and pass\",
	
	    \"sqlJsonTable\" : \"json_rpc\"
	    }";
}

unittest
{
	auto config1 = AppConfig(parseJsonString(configExample));
	
	AppConfig config2;
	
	config2.port = cast(ushort) 8888;
	config2.bindAddresses = ["::", "0.0.0.0"];
	config2.hostname = "";
	config2.maxConn = cast(uint) 50;
	config2.sqlAuth = "login and pass";
	config2.sqlJsonTable = "json_rpc";
	config2.sqlReconnectTime = 150;
	config2.sqlTimeout = 100;
	config2.sqlServers = [SqlConfig("sql1", cast(uint)1,""), SqlConfig("sql2", cast(uint)2, "",)];
	
	assert(config1 == config2, "Config unittest failed");
}
