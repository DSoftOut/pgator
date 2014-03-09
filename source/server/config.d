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

/**
* Represent configuration file.
*
* Authors: Zaramzan <shamyan.roman@gmail.com>
*/
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
	string vibelog = "http.log";
	
	@required
	string logname = "/var/log/"~APPNAME~"/"~APPNAME~".txt";
	
    /**	
    *   Deserializing config from provided $(B json) object.
    *
    *   Throws: InvalidConfig if json is incorrect (without info 
    *           about config file name)
    *
    *   Authors: Zaramzan <shamyan.roman@gmail.com>
    *            NCrashed <ncrashed@gmail.com>
    */
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
	
    /** 
    *   Parsing config from file $(B path).
    *
    *   Throws: InvalidConfig
    *
    *   Authors: Zaramzan <shamyan.roman@gmail.com>
    *            NCrashed <ncrashed@gmail.com>
    */
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

/// Describes basic sql info in AppConfig
struct SqlConfig
{
	@possible
	string name = null;
	
	@required
	size_t maxConn;
	
	@required
	string connString;
}

/** 
*   The exception is thrown when configuration parsing error occurs
*   (AppConfig constructor). Also encapsulates config file name.
*
*   Throws: InvalidConfig
*
*   Authors: Zaramzan <shamyan.roman@gmail.com>
*            NCrashed <ncrashed@gmail.com>
*/
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

/** 
*   The exception is thrown by $(B tryConfigPaths) is called and
*   all config file alternatives are failed to be loaded.
*
*   Also encapsulates a set of tried paths.
*
*   Authors: NCrashed <ncrashed@gmail.com>
*/
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

/**
*   Return value from $(B tryConfigPaths). Handles loaded config
*   and exact file $(B path).
*
*   Authors: NCrashed <ncrashed@gmail.com>
*/
alias Tuple!(immutable AppConfig, "config", string, "path") LoadedConfig;

/**
*   Takes range of paths and one at a time tries to load config from each one.
*   If the path doesn't exist, then the next candidate is checked. If the file
*   exists, but parsing or deserializing are failed, $(B InvalidConfig) exception
*   is thrown.
*
*   If functions go out of paths and none of them can be opened, then $(B NoConfigLoaded)
*   exception is thrown.
*   
*   Throws: NoConfigLoaded if can't load configuration file.
*           InvalidConfig if configuration file is invalid (first successfully opened)
*
*   Authors: NCrashed <ncrashed@gmail.com>
*            Zaramzan <shamyan.roman@gmail.com>
*/
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
*
*   Authors: NCrashed <ncrashed@gmail.com>
*/
AppConfig defaultConfig()
{
    AppConfig ret;
    ret.port = 8080;
    ret.maxConn = 50;
    ret.sqlServers = [SqlConfig("sql-server-1", 1, "dbname=rpc-proxy user=rpc-proxy password=123456")];
    ret.sqlAuth = ["login", "password"];
    ret.sqlTimeout = 1000;
    ret.sqlReconnectTime = 5000;
    ret.sqlJsonTable = "public.json_rpc";
    ret.bindAddresses = ["127.0.0.1"];
    ret.logname = "/var/log/"~APPNAME~"/"~APPNAME~".txt";
    return ret;
}


/**
*   Writes configuration $(B appConfig) to file path $(B name).
*   It is a wrapper function around $(B writeJson). 
*
*   Authors: NCrashed <ncrashed@gmail.com>
*            Zaramzan <shamyan.roman@gmail.com>
*/
bool writeConfig(AppConfig appConfig, string name)
{
    return writeJson(vibe.data.json.serializeToJson(appConfig), name);
}

/**
*   Writes down $(B json) to provided file $(B name).
*
*   Authors: NCrashed <ncrashed@gmail.com>
*            Zaramzan <shamyan.roman@gmail.com>
*/
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

/**
*   Generates and write down minimal configuration to $(B path).
*
*   Authors: NCrashed <ncrashed@gmail.com>
*            Zaramzan <shamyan.roman@gmail.com>
*/
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
