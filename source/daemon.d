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
import std.exception;
import std.file;
import std.process;
import std.path;
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
            int __libc_current_sigrtmin();
            char* strerror(int errnum);
            
            void signal_handler_daemon(int sig)
            {
                if(sig == SIGABRT || sig == SIGTERM || sig == SIGQUIT || sig == SIGINT || sig == SIGQUIT)
                {
                    savedLogger.logInfo(text("Signal ", to!string(sig), " caught..."));
                    savedTermListener();
                    deletePidFile(savedPidFile);
                    deleteLockFile(savedLockFile);
                    terminate(EXIT_SUCCESS);
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
    
    
        void enforceLockFile(string path, int userid)
        {
            if(path.exists)
            {
                savedLogger.logError(text("There is another pgator instance running: lock file is '",path,"'"));
                savedLogger.logInfo("Remove the file if previous instance if pgator has crashed");
                terminate(-1);
            } else
            {
                if(!path.dirName.exists)
                {
                    mkdirRecurse(path.dirName);
                }
                auto file = File(path, "w");
                file.close();
            }
            
            // if root, change permission on file to be able to remove later
            if (getuid() == 0 && userid >= 0) 
            {
                savedLogger.logDebug("Changing permissions for lock file: ", path);
                executeShell(text("chown ", userid," ", path.dirName));
                executeShell(text("chown ", userid," ", path));
            }
        }
        
        void deleteLockFile(string path)
        {
            if(path.exists)
            {
                scope(failure)
                {
                    savedLogger.logWarning(text("Failed to remove lock file: ", path));
                    return;
                }
                path.remove();
            }
        }
        
        void writePidFile(string path, int pid, uint userid)
        {
            scope(failure)
            {
                savedLogger.logWarning(text("Failed to write pid file: ", path));
                return;
            }
            
            if(!path.dirName.exists)
            {
                mkdirRecurse(path.dirName);
            }
            auto file = File(path, "w");
            scope(exit) file.close();
            
            file.write(pid);
            
            // if root, change permission on file to be able to remove later
            if (getuid() == 0 && userid >= 0) 
            {
                savedLogger.logDebug("Changing permissions for pid file: ", path);
                executeShell(text("chown ", userid," ", path.dirName));
                executeShell(text("chown ", userid," ", path));
            }
        }
        
        void deletePidFile(string path)
        {
            scope(failure)
            {
                savedLogger.logWarning(text("Failed to remove pid file: ", path));
                return;
            }
            path.remove();
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
                if (setgid(groupid) != 0)
                {
                    savedLogger.logError(text("setgid: Unable to drop group privileges: ", strerror(errno).fromStringz));
                    assert(false);
                }
                if (setuid(userid) != 0)
                {
                    savedLogger.logError(text("setuid: Unable to drop user privileges: ", strerror(errno).fromStringz));
                    assert(false);
                }
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
        //_d_critical_term();
        //_d_monitor_staticdtor();
    }

    exit(code);
}

/**
*   Forks daemon process with $(B progMain) main function and passes $(B args) to it. If daemon 
*   catches SIGHUP signal, $(B listener) delegate is called. If daemon catches SIGQUIT, SIGABRT,
*   or any other terminating sygnal, the termListener is called.
*
*   If application receives "real-time" signal $(B SIGROTATE) defined as SIGRTMIN+10, then $(B rotateListener) is called
*   to handle 'logrotate' utility.
* 
*   Daemon writes log message into provided $(B logger) and will close it while exiting.
*
*   File $(B pidfile) is used to write down PID of detached daemon. This file is usefull for interfacing with external 
*   tools thus it is only way to know daemon PID (for this moment). This file is removed while exiting.
*
*   File $(B lockfile) is used to track multiple daemon instances. If this file is exists, the another daemon is running
*   and pgator should exit immediately. 
*
*   $(B groupid) and $(B userid) are used to low privileges with run as root. 
*/
int runDaemon(shared ILogger logger, int delegate(string[]) progMain, string[] args, void delegate() listener
        , void delegate() termListener, void delegate() rotateListener, string pidfile, string lockfile
        , int groupid = -1, int userid = -1)
{
    savedLogger = logger;
    savedPidFile = pidfile;
    savedLockFile = lockfile;
    
    // Daemonize under Linux
    version (linux) 
    {
        // Handling lockfile
        enforceLockFile(lockfile, userid);
        scope(failure) deleteLockFile(lockfile);
    
        // Our process ID and Session ID
        pid_t pid, sid;

        // Fork off the parent process
        pid = fork();
        if (pid < 0) 
        {
            savedLogger.logError("Failed to start daemon: fork failed");
            deleteLockFile(lockfile);
            exit(EXIT_FAILURE);
        }
        // If we got a good PID, then we can exit the parent process.
        if (pid > 0) 
        {
            savedLogger.logInfo(text("Daemon detached with pid ", pid));
            
            // handling pidfile
            writePidFile(pidfile, pid, userid);
            
            exit(EXIT_SUCCESS);
        }
        
        // dropping root
        dropRootPrivileges(groupid, userid);
        
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
        scope(failure) deletePidFile(pidfile);
        
        // Create a new SID for the child process
        sid = setsid();
        if (sid < 0) terminate(EXIT_FAILURE);

        // Close out the standard file descriptors
        close(0);
        close(1);
        close(2);

        void bindSignal(int sig, sighandler_t handler)
        {
            enforce(signal(sig, handler) != SIG_ERR, text("Cannot catch signal ", sig));
        }
        
        savedTermListener = termListener;
        bindSignal(SIGABRT, &signal_handler_daemon);
        bindSignal(SIGTERM, &signal_handler_daemon);
        bindSignal(SIGQUIT, &signal_handler_daemon);
        bindSignal(SIGINT, &signal_handler_daemon);
        bindSignal(SIGQUIT, &signal_handler_daemon);
        
        savedListener = listener;
        bindSignal(SIGHUP, &signal_handler_daemon);
        
        savedRotateListener = rotateListener;
        bindSignal(SIGROTATE, &signal_handler_daemon);
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
        version(linux) 
        {
            deletePidFile(pidfile);
            deleteLockFile(lockfile);
        }
        terminate(code);
    }

    return 0;
}
