// Written in D programming language
/**
*
* Authors: Zaramzan <shamyan.roman@gmail.com>
*          NCrashed <ncrashed@gmail.com>
*/
module server.options;

import std.path;
import std.array;
import std.getopt;
import std.range;

import server.config;
import stdlog;
import util;

immutable class Options
{
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
	
	this(bool daemon, bool help, string configName, string genPath)
	{
	    mDaemon     = daemon;
	    mHelp       = help;
	    mConfigName = configName;
	    mGenPath    = genPath;
	}
	
	InputRange!string configPaths() @property
	{	
	    auto builder = appender!(string[]);
	    builder.put(buildPath("~/.config/rpc-sql-proxy", DEF_CONF_NAME).expandTilde);
	    
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
	
	string configName() @property
	{
		return buildNormalizedPath(mConfigName);
	}

	string genConfigPath() @property
	{
	    return buildNormalizedPath(mGenPath);
	}
	
	bool daemon() @property
	{
	    return mDaemon;
	}
	
	bool help() @property
	{
	    return mHelp;
	}
	
	immutable(Options) updateConfigPath(string path)
	{
	    return new immutable Options(daemon, help, path, genConfigPath);
	}
	
	private
	{
        enum helpMsg = "Server that transforms JSON-RPC calls into SQL queries for PostgreSQL.\n\n"
        "   rpc-proxy-server [arguments]\n"
        "   arguments =\n"
        "    --daemon - run in daemon mode (detached from tty).\n"
        "        Linux only.\n\n"
        "    --config=<string> - specifies config file name in\n"
        "        config directory.\n\n"
        "   --genConfig=<path> generate default config at the path\n\n"           
        "   --help - prints this message";
    	
    	enum DEF_CONF_NAME = APPNAME~".conf";
    	
    	bool mDaemon;
    	bool mHelp;
    
    	string mConfigName;
    	string mGenPath;
	}
}
