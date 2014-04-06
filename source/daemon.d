// Written in D programming language
/**
*    Boilerplate code to start linux daemon. Other platforms will
*    fallback to terminal mode.
*
*    See_Also: terminal
*    Copyright: © 2014 DSoftOut
*    License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*    Authors: NCrashed <ncrashed@gmail.com>
*/
module daemon;

import std.c.stdlib;
import std.stdio;
import std.conv;
version (linux) import std.c.linux.linux;
import dlogg.log;

private 
{
    void delegate() savedListener, savedTermListener;
    void delegate(int) savedUsrListener;
    
    shared ILogger savedLogger;
    
    extern(C)
    {
        /// These are for control of termination
        void _STD_monitor_staticdtor();
        void _STD_critical_term();
        void gc_term();
    
        version (linux) 
        {
            alias int pid_t;
    
            // daemon functions
            pid_t fork();
            int umask(int);
            int setsid();
            int close(int fd);
    
            // Signal trapping in Linux
            alias void function(int) sighandler_t;
            sighandler_t signal(int signum, sighandler_t handler);
    
            void termsig(int sig) 
            {
                savedLogger.logInfo(text("Signal ", sig, " is caught!"));
                savedTermListener();
                terminate(EXIT_SUCCESS);
            }
            
            void customHandler(int sig)
            {
                savedLogger.logInfo(text("Signal ", sig, " is caught!"));
                savedListener();
            }
            
            void usrDaemonHandler(int sig)
            {
                savedLogger.logInfo(text("User signal ", sig, " is caught!"));
                savedUsrListener(sig);
            }
        }
    }
}

private void terminate(int code) 
{
    savedLogger.logError("Daemon is terminating with code: " ~ to!string(code));
    savedLogger.finalize();
    
    gc_term();
    version (linux) 
    {
        _STD_critical_term();
        _STD_monitor_staticdtor();
    }

    exit(code);
}

/**
*   Forks daemon process with $(B progMain) main function and passes $(B args) to it. If daemon 
*   catches SIGHUP signal, $(B listener) delegate is called. If daemon catches SIGQUIT, SIGABRT,
*   or any other terminating sygnal, the termListener is called.
*
*   If USR1 or USR2 signal is caught, then $(B usrListener) is called with actual value of received signal.
* 
*   Daemon writes log message into provided $(B logger) and will close it while exiting.
*/
int runDaemon(shared ILogger logger, int delegate(string[]) progMain, string[] args, void delegate() listener,
        void delegate() termListener, void delegate(int) usrListener)
{
    savedLogger = logger;
    
    // Daemonize under Linux
    version (linux) 
    {
        // Our process ID and Session ID
        pid_t pid, sid;

        // Fork off the parent process
        pid = fork();
        if (pid < 0) {
            savedLogger.logError("Failed to start daemon: fork failed");
            exit(EXIT_FAILURE);
        }
        // If we got a good PID, then we can exit the parent process.
        if (pid > 0) {
            savedLogger.logInfo(text("Daemon detached with pid ", pid));
            exit(EXIT_SUCCESS);
        }
        
        // Change the file mode mask
        umask(0);
        savedLogger.minOutputLevel(LoggingLevel.Muted);
    } else
    {
        savedLogger.minOutputLevel(LoggingLevel.Notice);
        savedLogger.logError("Daemon mode isn't supported for this platform!");
    }

    version (linux) 
    {
        // Create a new SID for the child process
        sid = setsid();
        if (sid < 0) terminate(EXIT_FAILURE);

        // Close out the standard file descriptors
        close(0);
        close(1);
        close(2);

        savedTermListener = termListener;
        signal(SIGABRT, &termsig);
        signal(SIGTERM, &termsig);
        signal(SIGQUIT, &termsig);
        signal(SIGINT, &termsig);
        signal(SIGQUIT, &termsig);
        signal(SIGSEGV, &termsig);
        
        savedListener = listener;
        signal(SIGHUP, &customHandler);
        
//        savedUsrListener = usrListener;
//        signal(SIGUSR1, &usrDaemonHandler);
//        signal(SIGUSR2, &usrDaemonHandler);
    }

    savedLogger.logInfo("Server is starting in daemon mode...");
    int code = EXIT_FAILURE;
    try 
    {
        code = progMain(args);
    } catch (Exception ex) 
    {
        savedLogger.logError(text("Catched unhandled exception in daemon level: ", ex.msg));
        savedLogger.logError("Terminating...");
    } finally 
    {
        terminate(code);
    }

    return 0;
}