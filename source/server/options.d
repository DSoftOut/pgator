// Written in D programming language
/**
*
* Authors: Zaramzan <shamyan.roman@gmail.com>
*
*/
module server.options;

import std.path;
import std.getopt;
import std.range;

import server.config;

import stdlog;

import util;

class Options
{
	this(string[] args)
	{
		this.args = args;

		parse();
	}

	string[] configPaths() @property
	{	
		if (m_configDir)
		{
			return [buildNormalizedPath(m_configDir, configName)];
		}
		else
		{
			string[] arr = new string[0];

			foreach(dir; CONF_DIRS)
			{
				arr ~=buildNormalizedPath(dir, configName);
			}

			return arr;
		}
	}

	string configName() @property
	{
		if (m_configName)
		{
			return m_configName;
		}
		else
		{
			return DEF_CONF_NAME;
		}
	}

	string logPath() @property
	{
		return buildNormalizedPath(logDir, logName);
	}

	string logDir() @property
	{
		if (m_logDir)
		{
			return m_logDir;
		}
		else
		{
			return DEF_LOG_DIR;
		}
	}

	string logName() @property
	{
		if (m_logName)
		{
			return m_logName;
		}
		else
		{
			return DEF_LOG_NAME;
		}
	}

	bool daemon;

	bool help;

	string genPath = null;

	enum helpMsg = "Server that transforms JSON-RPC calls into SQL queries for PostgreSQL.
	rpc-proxy-server [arguments]
	arguments =
		--daemon - run in daemon mode (detached from tty).
			Linux only.
		
		--logDir=<string> - specifies logs dir.
			Default is '/var/log/rpc-sql-proxy'.
		
		--logName=<string> - specifies logname in log directory.
		
		--configDir=<string> - specifies config directory.
		
		--configName=<string> - specifies config file name in
			config directory.	    	
		
		--genConfig=<path> generate default config at path		    
		
		--help - prints this message";

	private:

	void parse()
	{
		getopt(args, std.getopt.config.passThrough,

						 "daemon", &daemon,

						 "logDir", &m_logDir,

					 	 "logName", &m_logName,

					 	 "help|h", &help,

					 	 "configDir", &m_configDir,

					 	 "configName", &m_configName,

					 	 "genConfig", &genPath);


	}

	bool verbose;

	bool quiet;

	string m_logName = null;

	string m_logDir = null;

	string m_configName = null;

	string m_configDir = null;

	string[] args;

}
