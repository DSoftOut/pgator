module app;

import stdlog;

version(unittest)
{
	void main()
	{
		
	}
}
else
{
	import std.stdio;
	import std.getopt;
	import daemon;
	import terminal;

	immutable help = `
	Server that transforms JSON-RPC calls in SQL queries for PostgreSQL.
		rpc-proxy-server [arguments]
		
		arguments = --daemon - run in daemon mode (detached from tty). 
						Linux only.
				    --log=<string> - specifies logging file name, 
				    	default is 'rpc-proxy-server.log'.
				    --help - prints this message
	`;
	
	int main(string[] args)
	{
		bool daemon = false;
		bool help = false;
		string logName = args[0]~".log";
		
		try
		{
			getopt(args, std.getopt.config.passThrough,
						 "daemon", &daemon,
					 	 "log", &logName,
					 	 "help", &help);
		} catch(Exception e)
		{
			writeln(e.msg); 
			writeln(help);
			return 0;
		}
		
		if(help)
		{
			writeln(help);
			return 0;
		}
		
		auto logger = new shared CLogger(logName);
		if(daemon) 
			return runDaemon(logger, (nargs) => 0, args, (){});
		else 
			return runTerminal(logger, (nargs) => 0, args, (){});
	}
}