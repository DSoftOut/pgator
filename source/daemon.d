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
    void delegate() savedListener, savedTermListener;
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
                savedLogger.logError("Signal %d caught..." ~ to!string(sig));
                savedTermListener();
                terminate(EXIT_SUCCESS);
            }
            
            void customHandler(int sig)
            {
                savedLogger.logInfo("Signal %d caught..." ~ to!string(sig));
                savedListener();
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
*   Daemon writes log message into provided $(B logger) and will close it while exiting.
*/
int runDaemon(shared ILogger logger, int delegate(string[]) progMain, string[] args, void delegate() listener,
        void delegate() termListener)
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
            savedLogger.logError(text("Daemon detached with pid ", pid));
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
        signal(SIGALRM, &termsig);
        signal(SIGBUS, &termsig);
        signal(SIGFPE, &termsig);
        signal(SIGILL, &termsig);
        signal(SIGFPE, &termsig);
        signal(SIGPIPE, &termsig);
        signal(SIGQUIT, &termsig);
        signal(SIGSEGV, &termsig);
        signal(SIGUSR1, &termsig);
        signal(SIGUSR2, &termsig);
        signal(SIGPOLL, &termsig);
        signal(SIGSYS, &termsig);
        signal(SIGXCPU, &termsig);
        signal(SIGXFSZ, &termsig);
        
        savedListener = listener;
        signal(SIGHUP, &customHandler);
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