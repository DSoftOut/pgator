// Written in D programming language
/**
*    Describes server attached to tty console. Specified delegate 
*    is called when SIGHUP signal is caught (linux only).
*
*    See_Also: daemon
*
*    Copyright: © 2014 DSoftOut
*    License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*    Authors: NCrashed <ncrashed@gmail.com>
*    
*/
module terminal;

import std.c.stdlib;
import std.stdio;
import std.conv;
import std.exception;
version (linux) import std.c.linux.linux;
import dlogg.log;

private 
{
    void delegate() savedListener, savedTermListener;
    void delegate() savedRotateListener;
    
    shared ILogger savedLogger;
    
    extern (C) 
    {
        version (linux) 
        {
            // Signal trapping in Linux
            alias void function(int) sighandler_t;
            sighandler_t signal(int signum, sighandler_t handler);
            int __libc_current_sigrtmin();
            
            void signal_handler_terminal(int sig)
            {
                if(sig == SIGABRT || sig == SIGTERM || sig == SIGQUIT || sig == SIGINT || sig == SIGQUIT)
                {
                    savedLogger.logInfo(text("Signal ", to!string(sig), " caught..."));
                    savedTermListener();
                } else if(sig == SIGHUP)
                {
                    savedLogger.logInfo(text("Signal ", to!string(sig), " caught..."));
                    savedListener();
                } else if(sig == SIGROTATE)
                {
                    savedLogger.logInfo(text("User signal ", sig, " is caught!"));
                    savedRotateListener();
                }
            }
        }
    }
    version(linux)
    {
        private immutable int SIGROTATE;
        static this()
        {
            SIGROTATE = __libc_current_sigrtmin + 10;
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
*    If application receives "real-time" signal $(B SIGROTATE) defined as SIGRTMIN+10, then $(B rotateListener) is called
*    to handle 'logrotate' utility.
*
*    Daemon writes log message into provided $(B logger).
*/
int runTerminal(shared ILogger logger, int delegate(string[]) progMain, string[] args, void delegate() listener,
    void delegate() termListener, void delegate() rotateListener)
{
    savedLogger = logger;
        
    version (linux) 
    {
        void bindSignal(int sig, sighandler_t handler)
        {
            enforce(signal(sig, handler) != SIG_ERR, text("Cannot catch signal ", sig));
        }
        
        savedTermListener = termListener;
        bindSignal(SIGABRT, &signal_handler_terminal);
        bindSignal(SIGTERM, &signal_handler_terminal);
        bindSignal(SIGQUIT, &signal_handler_terminal);
        bindSignal(SIGINT, &signal_handler_terminal);
        bindSignal(SIGQUIT, &signal_handler_terminal);
        
        savedListener = listener;
        bindSignal(SIGHUP, &signal_handler_terminal);
        
        savedRotateListener = rotateListener;
        bindSignal(SIGROTATE, &signal_handler_terminal);
    } 
    else
    {
        logger.logError("This platform doesn't support signals. Updating json-sql table by signal is disabled!");
    }

    logger.logInfo("Server is starting in terminal mode...");
    return progMain(args);
}