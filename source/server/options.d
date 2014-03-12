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
import stdlog;
import util;

/**
*   Application startup options. The main purpose is
*   to parse and store options about daemon mode,
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
    *   Options are: daemon or terminal mode, help message
    *   request, configuration file path and request for
    *   default configuration file generation.
    */
	this(string[] args)
	{	
	    bool pDaemon, pHelp;
	    string pConfigName, pGenPath;
	    
        getopt(args, std.getopt.config.passThrough,
                         "daemon",     &pDaemon,
                         "help|h",     &pHelp,
                         "config",     &pConfigName,
                         "genConfig",  &pGenPath);
        
        mDaemon     = pDaemon;
        mHelp       = pHelp;
        mConfigName = pConfigName;
        mGenPath    = pGenPath;
	}
	
	/**
	*  Verbose creation from native D types.
	*  Params:
	*  daemon      = is program should start in daemon mode
	*  help        = is program should show help message and exit
	*  configName  = configuration file name
	*  genPath     = is program should generate config at specified path and exit
	*/
	this(bool daemon, bool help, string configName, string genPath) pure nothrow
	{
	    mDaemon     = daemon;
	    mHelp       = help;
	    mConfigName = configName;
	    mGenPath    = genPath;
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
	
	/// Configuration full file name
	string configName() @property pure nothrow @safe
	{
		return buildNormalizedPath(mConfigName);
	}
	
	/// Path where to generate configuration
	string genConfigPath() @property pure nothrow @safe
	{
	    return buildNormalizedPath(mGenPath);
	}
	
	/// Is application should run in daemon mode
	bool daemon() @property pure nothrow @safe
	{
	    return mDaemon;
	}
	
	/// Is application should show help message and exit
	bool help() @property pure nothrow @safe
	{
	    return mHelp;
	}
	
	/// Application help message
    enum helpMsg = "Server that transforms JSON-RPC calls into SQL queries for PostgreSQL.\n\n"
    "   pgator [arguments]\n"
    "   arguments =\n"
    "    --daemon - run in daemon mode (detached from tty).\n"
    "        Linux only.\n\n"
    "    --config=<string> - specifies config file name in\n"
    "        config directory.\n\n"
    "   --genConfig=<path> generate default config at the path\n\n"           
    "   --help - prints this message";
    
    /**
    *   Creates new options with updated configuration $(B path).
    */
	immutable(Options) updateConfigPath(string path) pure nothrow
	{
	    return new immutable Options(daemon, help, path, genConfigPath);
	}
	
	private
	{
    	enum DEF_CONF_NAME = APPNAME~".conf";
    	
    	bool mDaemon;
    	bool mHelp;
    
    	string mConfigName;
    	string mGenPath;
	}
}
