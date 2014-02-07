
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

import core.time;

import vibe.data.json;
import vibe.core.log;

enum CONFIG_PATH = "config.json";

struct AppConfig
{
	this(in Json src)
	{
		foreach(string k, v; src)
		{
			if (k == "port")
			{
				port = v.to!ushort();
			}
			else if (k == "maxConn")
			{
				maxConn = v.to!uint();
			}
			else if (k == "sqlTimeout")
			{
				sqlTimeout = dur!"msecs"(v.to!uint());
			}
			else if (k == "sqlAuth")
			{
				sqlAuth = v.to!string();
			}
			else if (k == "sqlJsonTable")
			{
				sqlJsonTable = v.to!string();
			}
			else if (k == "sqlServers")
			{
				foreach (serv; v.get!(Json[]))
				{
					sqlServers ~= SqlConfig(serv);
				}
			}
			else
			{
				throw new InvalidConfig("Config fields do not complete");
			}
		}
		
		optional = AppOptionalConfig(src);
	}
	
	this (in string path)
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
	
	version(unittest)
	{
		this(ushort port, uint maxConn, SqlConfig[] conf, Duration sqlTimeout, string sqlAuth, string sqlJsonTable,
			AppOptionalConfig optConf)
		{
			this.port = port;
			this.maxConn = maxConn;
			this.sqlServers = conf;
			this.sqlTimeout = sqlTimeout;
			this.sqlAuth = sqlAuth;
			this.sqlJsonTable = sqlJsonTable;
			this.optional = optConf;
		}
	}
	
	Json parseJson(in string jsonStr)
	{
		try
		{
			return parseJsonString(jsonStr);
		}
		catch (Exception ex)
		{
			logError(ex.msg);
			throw new Exception("json config parse error");
		}
	}
	
	void fromJson(in Json src)
	{
		
	}
		
	immutable ushort port;
	
	immutable uint maxConn;
	
	immutable SqlConfig[] sqlServers;
	
	immutable Duration sqlTimeout;
	
	Duration sqlWait() @property
	{
		if (optional.isExistSqlWait)
		{
			return optional.sqlWait;
		}
		else return sqlTimeout;
	}
	
	
	immutable string sqlAuth;
	
	immutable string sqlJsonTable;
	
	immutable AppOptionalConfig optional;	
}


struct AppOptionalConfig
{
	this(in Json src)
	{
		foreach(string k, v; src)
		{
			if (k == "sqlWait")
			{
				sqlWait = dur!"msecs"(v.to!uint());
				existSqlWait = true;
			}
			else if (k == "hostname")
			{
				hostname = v.to!string();
				existHostname = true;
			}
			else if (k == "bindAddresses")
			{
				foreach(addr; v.get!(Json[])())
				{
					bindAddresses ~= addr.to!string();
					existBindAddr = true;
				}
			}
		}
	}
	
	version(unittest)
	{
		this(string[] addrs, string hostname, Duration sqlWait)
		{
			bindAddresses = addrs;
			this.existBindAddr = true;
			this.hostname = hostname;
			this.existHostname = true;
			this.sqlWait = sqlWait;
			this.existSqlWait = true;
		}
	}
	
	immutable string[] bindAddresses;
	
	private immutable bool existBindAddr;
	
	bool isExistBindAddresses() @property
	const
	{
		return existBindAddr;
	}
	
	immutable string hostname;
	
	private immutable bool existHostname;
	
	bool isExistHostname() @property
	const
	{
		return existHostname;
	}
	
	immutable Duration sqlWait;
	
	private immutable bool existSqlWait;
	
	bool isExistSqlWait() @property
	const
	{
		return existSqlWait;
	}
	
}

struct SqlConfig
{
	this(in Json src)
	{
		foreach(string k, v; src)
		{
			if (k == "name")
			{
				name = v.to!string();
			}
			else if (k == "connString")
			{
				connString = v.to!string;
			}
			else if (k == "maxConn")
			{
				maxConn = v.to!uint;
			}
		}
	}
	
	version (unittest)
	{
		this(string name, string connString, uint maxConn)
		{
			this.name = name;
			this.connString = connString;
			this.maxConn = maxConn;
		}
	}
	
	immutable string name;
	
	immutable string connString;
	
	immutable uint maxConn;	
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
	
	    \"sqlWait\": 150,
	
	    \"sqlAuth\" : \"login and pass\",
	
	    \"sqlJsonTable\" : \"json_rpc\"
	    }";
}

unittest
{
	import std.stdio;
	import core.time;
	import vibe.data.json;
	
	auto conf1 = AppConfig( cast(ushort)8888, 
		
		cast(uint)50, 
		
		[
			SqlConfig("sql1", "", cast(uint)1), 
			SqlConfig("sql2", "", cast(uint)2)
		], 
		
		dur!"msecs"(100),
		
		"login and pass", 
		
		"json_rpc", 
		
		AppOptionalConfig(["::", "0.0.0.0"], "", dur!"msecs"(150))
	);
	
	auto json = parseJsonString(configExample);
	auto conf2 = AppConfig(json);
	
	assert(conf1 == conf2, "Config unittest failed");
}