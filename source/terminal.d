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
version (linux) 
{
    import std.c.linux.linux;
    import core.sys.linux.errno;
}
import dlogg.log;
import util;

private 
{
    void delegate() savedListener, savedTermListener;
    void delegate() savedRotateListener;
    
    shared ILogger savedLogger;
    
    string savedPidFile;
    string savedLockFile;
    
    extern (C) 
    {
        version (linux) 
        {
            // Signal trapping in Linux
            alias void function(int) sighandler_t;
            sighandler_t signal(int signum, sighandler_t handler);
            int __libc_current_sigrtmin();
            char* strerror(int errnum);
            
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
        
        void dropRootPrivileges(int groupid, int userid)
        {
            if (getuid() == 0) 
            {
                if(groupid < 0 || userid < 0)
                {
                    savedLogger.logWarning("Running as root, but doesn't specified groupid and/or userid for"
                        " privileges lowing!");
                    return;
                }
                
                savedLogger.logInfo("Running as root, dropping privileges...");
                // process is running as root, drop privileges 
                if (setegid(groupid) != 0)
                {
                    savedLogger.logError(text("setgid: Unable to drop group privileges: ", strerror(errno).fromStringz));
                    assert(false);
                }
                if (seteuid(userid) != 0)
                {
                    savedLogger.logError(text("setuid: Unable to drop user privileges: ", strerror(errno).fromStringz));
                    assert(false);
                }
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
*    If application receives "real-time" signal $(B SIGROTATE) defined as SIGRTMIN+10, then $(B rotateListener) is called
*    to handle 'logrotate' utility.
*
*    Daemon writes log message into provided $(B logger).
*
*   $(B groupid) and $(B userid) are used to low privileges with run as root. 
*/
int runTerminal(shared ILogger logger, int delegate(string[]) progMain, string[] args, void delegate() listener,
    void delegate() termListener, void delegate() rotateListener, int groupid = -1, int userid = -1)
{
    savedLogger = logger;
    
    // dropping root
    dropRootPrivileges(groupid, userid);
    
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