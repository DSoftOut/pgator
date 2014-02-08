// Written in D programming language
/**
*    Boilerplate code to start linux daemon. Other platforms will
*    fallback to terminal mode.
*
*    See_Also: terminal
*    Authors: NCrashed <ncrashed@gmail.com>
*
*/
module daemon;

import std.c.stdlib;
import std.stdio;
import std.conv;
version (linux) import std.c.linux.linux;
import log;

private 
{
    void delegate() savedListener;
    
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
    
            void termHandler(int sig) 
            {
                logError("Signal %d caught..." ~ to!string(sig));
                terminate(EXIT_SUCCESS);
            }
            
            void customHandler(int sig)
            {
                logInfo("Signal %d caught..." ~ to!string(sig));
                savedListener();
            }
        }
    }
}

private void terminate(int code) 
{
    logError("Daemon is terminating with code: " ~ to!string(code));
    shutdownLoggingSystem();
    
    gc_term();
    version (linux) 
    {
        _STD_critical_term();
        _STD_monitor_staticdtor();
    }

    exit(code);
}

/**
*    Forks daemon process with $(B progMain) main function and passes $(B args) to it. Function also
*    initializes logging system with $(B logFile) name. If daemon catches SIGHUP signal, $(B listener)
*    delegate is called.
*/
int runDaemon(string logFile, int function(string[]) progMain, string[] args, void delegate() listener)
{
    // Daemonize under Linux
    version (linux) 
    {
        // Our process ID and Session ID
        pid_t pid, sid;

        // Fork off the parent process
        pid = fork();
        if (pid < 0) {
            writeln("Failed to start daemon: fork failed");
            exit(EXIT_FAILURE);
        }
        // If we got a good PID, then we can exit the parent process.
        if (pid > 0) {
            writeln("Daemon detached with pid ", pid);
            exit(EXIT_SUCCESS);
        }
        
        // Change the file mode mask
        umask(0);
        initLoggingSystem(logFile, true);
    } else
    {
        initLoggingSystem(logFile, false);
        logError("Daemon mode isn't supported for this platform!");
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

        signal(SIGABRT, &termHandler);
        signal(SIGTERM, &termHandler);
        signal(SIGQUIT, &termHandler);
        signal(SIGINT, &termHandler);
        
        savedListener = listener;
        signal(SIGHUP, &customHandler);
    }

    logInfo("Server is starting in daemon mode...");
    int code = EXIT_FAILURE;
    try 
    {
        code = progMain(args);
    } catch (Exception ex) 
    {
        logError("Catched unhandled exception in daemon level: " ~ ex.msg);
        logError("Terminating...");
    } finally 
    {
        terminate(code);
    }

    return 0;
}