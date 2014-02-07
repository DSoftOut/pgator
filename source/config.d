
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

private mixin template t_field(T, alias fieldName)
{
	mixin("private "~T.stringof~" m_"~fieldName~";");
	
	mixin("private bool f_"~fieldName~";");
	
	mixin(T.stringof~" "~fieldName~"() @property { return m_"~fieldName~";}");
	
	mixin("void "~fieldName~"("~T.stringof~" f) @property { m_"~fieldName~"= f; f_"~fieldName~"=true;}");
}

struct AppConfig
{
	mixin t_field!(ushort, "port");
	
	mixin t_field!(uint, "maxConn");
	
	mixin t_field!(SqlConfig[], "sqlServers");
	
	mixin t_field!(Duration, "sqlTimeout");
	
	mixin t_field!(string, "sqlAuth");
	
	mixin t_field!(string, "sqlJsonTable");
	
	mixin t_field!(AppOptionalConfig, "optional");
	
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
				SqlConfig[] sqlServers = new SqlConfig[0];
				foreach (serv; v.get!(Json[]))
				{
					sqlServers ~= SqlConfig(serv);
				}
				
				this.sqlServers = sqlServers;
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
	
	Duration sqlWait() @property
	{
		if (optional.isExistSqlWait)
		{
			return optional.sqlWait;
		}
		else return sqlTimeout;
	}
	
	
	private bool isComplete()
	{
		return f_port && f_maxConn && f_sqlServers && f_sqlTimeout && f_sqlAuth && f_sqlJsonTable;
	}	
}


struct AppOptionalConfig
{
	mixin t_field!(string[], "bindAddresses");
	
	mixin t_field!(string, "hostname");
	
	mixin t_field!(Duration, "sqlWait");
	
	this(in Json src)
	{
		foreach(string k, v; src)
		{
			if (k == "sqlWait")
			{
				sqlWait = dur!"msecs"(v.to!uint());
			}
			else if (k == "hostname")
			{
				hostname = v.to!string();
			}
			else if (k == "bindAddresses")
			{
				string[] bindAddresses = new string[0];
				foreach(addr; v.get!(Json[])())
				{
					bindAddresses ~= addr.to!string();
				}
				this.bindAddresses = bindAddresses;
			}
		}
	}
	
	version(unittest)
	{
		this(string[] addrs, string hostname, Duration sqlWait)
		{
			bindAddresses = addrs;
			this.hostname = hostname;
			this.sqlWait = sqlWait;
		}
	}
	
	
	
	bool isExistBindAddresses() @property
	const
	{
		return f_bindAddresses;
	}
	
	bool isExistHostname() @property
	const
	{
		return f_hostname;
	}
	
	
	bool isExistSqlWait() @property
	const
	{
		return f_sqlWait;
	}
	
	bool isEmpty()
	const
	{
		return !(f_bindAddresses || f_hostname || f_sqlWait);
	}
	
	
	
}

struct SqlConfig
{
	mixin t_field!(string, "name");
	
	mixin t_field!(string, "connString");
	
	mixin t_field!(uint, "maxConn");
	
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