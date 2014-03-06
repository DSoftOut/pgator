
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
import std.range;
import std.typecons;
import std.conv;

import vibe.data.json;
import vibe.core.log;

import util;

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
	string[] bindAddresses = null;
	
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
        try
        {
            this = deserializeFromJson!AppConfig(json);
        }
        catch(Exception e)
        {
            throw new InvalidConfig("", e.msg);
        }
	}
	
	this(string path) immutable
	{
	    auto str = File(path, "r").byLine.join.idup;
		auto json = parseJson(str);

		AppConfig conf;
		try
		{
		    conf = deserializeFromJson!AppConfig(json);
		}
		catch(Exception e)
		{
    		throw new InvalidConfig(path, e.msg);
		}
		
		port             = conf.port;
		maxConn          = conf.maxConn;
		sqlServers       = conf.sqlServers.idup;
		sqlAuth          = conf.sqlAuth.idup;
		sqlTimeout       = conf.sqlTimeout;
		sqlJsonTable     = conf.sqlJsonTable;
		bindAddresses    = conf.bindAddresses.idup;
		hostname         = conf.hostname;
		sqlReconnectTime = conf.sqlReconnectTime;
		vibelog          = conf.vibelog;
		logname          = conf.logname;
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

class InvalidConfig : Exception
{
    private string mConfPath;
    
	@safe pure nothrow this(string confPath, string msg, string file = __FILE__, size_t line = __LINE__)
	{
	    mConfPath = confPath;
		super(msg, file, line);
	}
	
	string confPath() @property
	{
	    return mConfPath;
	}
}

class NoConfigLoaded : Exception
{
    private string[] mConfPaths;
    
    @safe pure nothrow this(string[] confPaths, string file = __FILE__, size_t line = __LINE__)
    {
        mConfPaths = confPaths;
        
        string msg;
        {
            scope(failure) msg = "<Internal error while collecting error message, report this bug!>";
            msg = text("Failed to load configuration file from one of following paths: ", confPaths);
        }
        super(msg, file, line);
    }
    
    string[] confPaths() @property
    {
        return mConfPaths;
    }
}

alias Tuple!(immutable AppConfig, "config", string, "path") LoadedConfig;

LoadedConfig tryConfigPaths(R)(R paths)
    if(isInputRange!R && is(ElementType!R == string))
{
    foreach(path; paths)
    {
        try
        {
            return LoadedConfig(immutable AppConfig(path), path);
        }
        catch(InvalidConfig e)
        {
            throw e;
        }
        catch(Exception e)
        {
            continue;
        }
    }
    
    throw new NoConfigLoaded(paths.array);
}
    
/**
*   Returns config example to be edited by end user.
*   
*   This configuration is generated only if explicit 
*   key is passed to the application.
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

//bool writeConfig(AppConfig appConfig, string name)
//{
//    return writeJson(vibe.data.json.serializeToJson(appConfig), name);
//}

bool writeJson(Json json, string name)
{
    scope(failure) return false;
    
    auto dir = name.dirName;
    if (!dir.exists)
    {
        dir.mkdirRecurse;
    }
  
    auto file = new File(name, "w");
    scope(exit) file.close();
          
    auto builder = appender!string;
    writePrettyJsonString(builder, json, 0);
    file.writeln(builder.data);
    
    return true;
}

void genConfig(string path)
{
	if (!writeJson(defaultConfig.serializeRequiredToJson, path))
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
