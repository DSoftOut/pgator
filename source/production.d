/**
*   Application contains four build configurations: production, unittests and test client.
*
*   Unittests configuration produce dummy executable the only purpose is to run module unittests.
*
*   Production configuration is main and default configuration. There the configuration files and
*   argument parameters are parsed, daemon or terminal mode is selected and actual rpc server starts.
*
*   Copyright: © 2014 DSoftOut
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*            Zaramzan <shamyan.roman@gmail.com>
*/
module production;

version(unittest)
{
    void main() {}
}
else
{
    import std.stdio;
    import std.typecons;
    import std.concurrency;
	import core.time;
	import server.server;
	import server.options;
	import server.config;
	
	import daemon;
	import terminal;
	import dlogg.strict;
	
	immutable struct LoadedConfig
    {
        AppConfig config;
        Options options;
    }
    
	LoadedConfig loadConfig(immutable Options options)
	{
        if(options.configName != "")
        {
            return LoadedConfig(immutable AppConfig(options.configName), options);
        }
        else
        {
            auto res = tryConfigPaths(options.configPaths); 
            return LoadedConfig(res.config, options.updateConfigPath(res.path));
        }
	}
	
	int main(string[] args)
	{	
		auto options = new immutable Options(args);
		
		if (options.help)
		{
			writeln(options.helpMsg);
			return 0;
		}
		
		if (options.genConfigPath != "")
		{
			genConfig(options.genConfigPath);
			return 0;
		}
		
		try
		{
		    auto loadedConfig = loadConfig(options);
            auto logger = new shared StrictLogger(loadedConfig.config.logname, StrictLogger.Mode.Append);
            auto app = new shared Application(logger, loadedConfig.options, loadedConfig.config);
            
            enum mainFunc = (string[] args)
            {
                int res;
                do
                {
                    res = app.run;
                } while(receiveTimeout(dur!"msecs"(1000), 
                        // bug, should be fixed in 2.067
                        //  (shared(Application) newApp) {app = newApp;}
                        (Variant v) 
                        {
                            auto newAppPtr = v.peek!(shared(Application)); assert(newAppPtr);
                            app = *newAppPtr;
                        }));
                
                logger.logDebug("Exiting main");
                return res;
            };
            
            enum termFunc = ()
            {
                auto newApp = app.restart;
                send(thisTid, newApp);
            };

            if(options.daemon) 
                return runDaemon(logger, mainFunc, args, termFunc
                    , (){app.finalize;}, () {app.logger.reload;}
                    , options.pidFile, options.lockFile
                    , loadedConfig.config.groupid, loadedConfig.config.userid);
            else 
                return runTerminal(logger, mainFunc, args, termFunc
                    , (){app.finalize;}, () {app.logger.reload;}
                    , loadedConfig.config.groupid, loadedConfig.config.userid);
	    }
	    catch(InvalidConfig e)
        {
            writeln("Configuration file at '", e.confPath, "' is invalid! ", e.msg);
            return 1;
        }
        catch(NoConfigLoaded e)
        {
            writeln(e.msg);
            return 1;
        }
        catch(Exception e)
        {
            writeln("Failed to load configuration file at '", options.configName, "'! Details: ", e.msg);
            return 1;
        }
	}
}
