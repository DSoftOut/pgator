// Written in D programming language
/**
*   Module describes application startup options.
*
*   Copyright: © 2014 DSoftOut
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: Zaramzan <shamyan.roman@gmail.com>
*            NCrashed <ncrashed@gmail.com>
*/
module server.options;

import std.path;
import std.array;
import std.getopt;
import std.range;

import server.config;
import dlogg.log;
import util;

private enum PGATOR_VERSION = import("current-pgator.version");
private enum PGATOR_BACKEND_VERSION = import("current-pgator-backend.version");

/**
*   Application startup options. The main purpose is
*   to parse and store options about
*   configuration file path and some other options that
*   needed in application startup.
*
*   As the class is immutable, it can be passed between
*   threads safely.
*/
immutable class Options
{
    /**
    *   Application $(B args) arguments parsing.
    *   
    *   Options are: help message
    *   request, configuration file path and request for
    *   default configuration file generation.
    */
	this(string[] args)
	{	
	    bool pHelp, pVersion;
	    string pConfigName, pGenPath;
	    
        getopt(args, std.getopt.config.passThrough,
                         "help|h",     &pHelp,
                         "config",     &pConfigName,
                         "genConfig",  &pGenPath,
                         "version",    &pVersion);
        
        mHelp       = pHelp;
        mConfigName = pConfigName;
        mGenPath    = pGenPath;
        mVersion    = pVersion;
	}
	
	/**
	*  Verbose creation from native D types.
	*  Params:
	*  help        = is program should show help message and exit
	*  configName  = configuration file name
	*  genPath     = is program should generate config at specified path and exit
	*  showVersion = is program should show it version 
	*/
	this(bool help, string configName, string genPath
	    , bool showVersion) pure nothrow
	{
	    mHelp       = help;
	    mConfigName = configName;
	    mGenPath    = genPath;
        mVersion    = showVersion;
	}
	
	/**
	*  Returns all paths where application should try to find
	*  configuration file.
	*
	*  Note: Application should use this when and only when
	*        configName is not set.
	*/
	InputRange!string configPaths() @property
	{	
	    auto builder = appender!(string[]);
	    builder.put(buildPath("~/.config", APPNAME, DEF_CONF_NAME).expandTilde);
	    
	    version(Posix)
	    {
	        builder.put(buildPath("/etc", DEF_CONF_NAME));
	    }
	    version(Windows)
	    {
	        builder.put(buildPath(".", DEF_CONF_NAME));
	    }
	    
		return builder.data.inputRangeObject;
	}
	
	@property pure nothrow @safe
	{
    	/// Configuration full file name
    	string configName() 
    	{
    		return buildNormalizedPath(mConfigName);
    	}
    	
    	/// Path where to generate configuration
    	string genConfigPath()
    	{
    	    return buildNormalizedPath(mGenPath);
    	}
    	
    	/// Is application should show help message and exit
    	bool help()
    	{
    	    return mHelp;
    	}
    	
    	/// Is program should show it version and exit
    	bool showVersion()
    	{
    	    return mVersion;
    	}
	}
	
	/// Application help message
    enum helpMsg = "Server that transforms JSON-RPC calls into SQL queries for PostgreSQL.\n\n"
    ~ versionMsg ~ "\n"
    "   pgator [arguments]\n"
    "   arguments =\n"
    "    --config=<string> - specifies config file name in\n"
    "                        config directory.\n"
    "   --genConfig=<path> - generates default config at the path\n"           
    "   --help             - prints this message\n"
    "   --version          - shows program version";
    
    /// Application version message
    enum versionMsg = 
    "build-version: " ~ PGATOR_VERSION ~ 
    "backend-version: " ~ PGATOR_BACKEND_VERSION;
    
    /**
    *   Creates new options with updated configuration $(B path).
    */
	immutable(Options) updateConfigPath(string path) pure nothrow
	{
	    return new immutable Options(help, path, genConfigPath, showVersion);
	}
	
	private
	{
    	enum DEF_CONF_NAME = APPNAME~".conf";
    	
    	bool mHelp;
    	bool mVersion;
    	
    	string mConfigName;
    	string mGenPath;
	}
}
