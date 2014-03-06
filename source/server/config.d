
// Written in D programming language
/**
* Config reading system.
*
* Ctor $(B AppConfig(string)) create a config from file.
*
*
* Authors: Zaramzan <shamyan.roman@gmail.com>
*/
module server.config;

import std.exception;
import std.stdio;
import std.path;
import std.file;

import vibe.data.json;
import vibe.core.log;

import util;

enum DEF_CONF_NAME = APPNAME ~ ".conf";

version (linux)
{
	string[] CONF_DIRS() @property
	{
		return [CONF_HOME, ETC];
	}

	private:

	enum ETC = "/etc/" ~ APPNAME;

	enum HOME = "~/.config/" ~ APPNAME;

	string CONF_HOME() @property
	{
		return HOME.expandTilde;
	}
}
else
{
	string[] CONF_DIRS() @property
	{
		return ["."];
	}
}

struct AppConfig
{
	@required
	ushort port;

	@required
	uint maxConn;

	@required
	SqlConfig[] sqlServers;

	@required
	string[] sqlAuth;

	@required
	uint sqlTimeout; //ms

	@required
	string sqlJsonTable;

	@possible
	string[] bindAddresses = null; //["127.0.0.1"];

	@possible
	string hostname = null;

	@possible
	int sqlReconnectTime = -1; //ms

	@possible
	string vibelog = "http.txt";

	@required
	string logname = "log.txt";

	this(Json json)
	{

		this = tryEx!(InvalidConfig, deserializeFromJson!AppConfig)(json);
	}

	this(string path)
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
}

struct SqlConfig
{
	@possible
	string name = null;

	@required
	size_t maxConn;

	@required
	string connString;
}

class InvalidConfig:Exception
{
	@safe pure nothrow this(string msg = null, string file = __FILE__, size_t line = __LINE__)
	{
		super(msg, file, line);
	}
}

/**
*   Returns config example to be edited by end user.
*   
*   If the application cannot find configuration file, it
*   terminates and ask an user to edit the default configuration
*   file that is written to the specified place.
*/
AppConfig defaultConfig()
{
    AppConfig ret;
    ret.port = 8080;
    ret.maxConn = 100;
    ret.sqlServers = [SqlConfig("sql-server-1", 1, "dbname=rpc-proxy user=rpc-proxy password=123456")];
    ret.sqlAuth = ["login", "password"];
    ret.sqlTimeout = 1000;
    ret.sqlReconnectTime = 5000;
    ret.sqlJsonTable = "public.json_rpc";
    ret.bindAddresses = ["127.0.0.1"];
    ret.logname = "log.txt";
    return ret;
}

bool writeConfig(AppConfig appConfig, string name, string dir)
{
	scope(failure)
	{
		return false;
	}

	if (!dir.exists)
	{
		dir.mkdirRecurse;
	}

	string fullPath = buildNormalizedPath(dir, name);

	auto file = new File(fullPath, "w");

	scope(exit) file.close();

    auto builder = appender!string;
    
    writePrettyJsonString(builder, vibe.data.json.serializeToJson(appConfig), 0);
    
    file.writeln(builder.data);
    
    return true;

}

bool writeJsonConfig(Json json, string name, string dir)
{
	scope(failure)
	{
		return false;
	}

	if (!dir.exists)
	{
		dir.mkdirRecurse;
	}

	string fullPath = buildNormalizedPath(dir, name);

	auto file = new File(fullPath, "w");

	scope(exit) file.close();

    auto builder = appender!string;
    
    writePrettyJsonString(builder, json, 0);
    
    file.writeln(builder.data);
    
    return true;

}

void genConfig(string path)
{
	if (!writeJsonConfig(defaultConfig.serializeRequiredToJson, path, ""))
	{
		std.stdio.writeln("Can't generate config at ", path);
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
	
	    \"sqlAuth\" : [\"login\",\"password\"],
	
	    \"sqlJsonTable\" : \"json_rpc\",

	    \"logname\" : \"log.txt\"
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
	config2.sqlAuth = ["login", "password"];
	config2.sqlJsonTable = "json_rpc";
	config2.logname = "log.txt";
	config2.sqlReconnectTime = 150;
	config2.sqlTimeout = 100;
	config2.sqlServers = [SqlConfig("sql1", cast(size_t)1,""), SqlConfig("sql2", cast(size_t)2, "",)];

	assert(config1 == config2, "Config unittest failed");
}
