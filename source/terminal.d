// Written in D programming language
/**
*    Describes server attached to tty console. Specified delegate 
*    is called when SIGHUP signal is caught (linux only).
*
*    See_Also: daemon
*    Authors: NCrashed <ncrashed@gmail.com>
*    
*/
module terminal;

import std.c.stdlib;
import std.stdio;
import std.conv;
version (linux) import std.c.linux.linux;
import log;

private 
{
    void delegate() savedListener, savedTermListener;
    void delegate(int) savedUsrListener;
    
    shared ILogger savedLogger;
    
    extern (C) 
    {
        version (linux) 
        {
            // Signal trapping in Linux
            alias void function(int) sighandler_t;
            sighandler_t signal(int signum, sighandler_t handler);
            
            void termHandler(int sig)
            {
                savedLogger.logInfo(text("Signal ", to!string(sig), " caught..."));
                savedTermListener();
            }
            
            void sighandler(int sig)
            {
                savedLogger.logInfo(text("Signal ", to!string(sig), " caught..."));
                savedListener();
            }
            
            void usrTerminalHandler(int sig)
            {
                savedLogger.logInfo(text("User signal ", sig, " is caught!"));
                savedUsrListener(sig);
            }
        }
    }
}

/**
*    Run application as casual process (attached to tty) with $(B progMain) main function and passes $(B args) into it. 
*    If daemon catches SIGHUP signal, $(B listener) delegate is called (available on linux only).
*
*    If application receives some kind of terminating signal, the $(B termListener) is called. $(B termListener) should
*    end $(B progMain) to be able to clearly shutdown the application.
*
*   If USR1 or USR2 signal is caught, then $(B usrListener) is called with actual value of received signal.
*
*    Daemon writes log message into provided $(B logger).
*/
int runTerminal(shared ILogger logger, int delegate(string[]) progMain, string[] args, void delegate() listener,
    void delegate() termListener, void delegate(int) usrListener)
{
    savedLogger = logger;
        
    version (linux) 
    {
        savedTermListener = termListener;
        signal(SIGABRT, &termHandler);
        signal(SIGTERM, &termHandler);
        signal(SIGQUIT, &termHandler);
        signal(SIGINT, &termHandler);
        signal(SIGQUIT, &termHandler);
        signal(SIGSEGV, &termHandler);
        
        savedListener = listener;
        signal(SIGHUP, &sighandler);
        
        savedUsrListener = usrListener;
        signal(SIGUSR1, &usrTerminalHandler);
        signal(SIGUSR2, &usrTerminalHandler);
    } 
    else
    {
        logger.logError("This platform doesn't support signals. Updating json-sql table by signal is disabled!");
    }

    logger.logInfo("Server is starting in terminal mode...");
    return progMain(args);
}