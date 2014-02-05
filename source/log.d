// Written in D programming language
/**
*	Logging system designed to operate in concurrent application.
*
*	The system should be initialized with $(B initLoggingSystem) function.
*	There is no need to call shutdown function as it is happen in module
*	destructor.
*
*	Example:
*	---------
*	void testThread()
*	{
*		foreach(j; 1 .. 50)
*		{
*			logInfo(to!string(j));
*			logError(to!string(j));
*		}
*	}	
*
*	foreach(i; 1 .. 50)
*	{
*		spawn(&testThread);
*	}
*	---------
*
*	Authors: NCrashed <ncrashed@gmail.com>
*
*/
module log;

import std.concurrency;
import std.conv;
import std.datetime;
import std.file;
import std.path;
import std.stdio;
import vibe.core.concurrency;
import vibe.core.file;

/**
*	Initializes logging system. Should be called once. Can throw if
*	something goes wrong.
*
*	Params:
*	logFileName 	= File name to write the log.
*	daemonMode      = If true logging functions doesn't writes to stdout and stderr.
*/
void initLoggingSystem(string logFileName, bool daemonMode = false)
{
	if(logSys !is null) shutdownLoggingSystem();
	
	logSys = new shared LogSystem();
	auto s = logSys.lock();
	s.file = openFile(logFileName, FileMode.createTrunc);
	s.daemonMode = daemonMode;
}

private void shutdownLoggingSystem() nothrow
{
	scope(failure) {}
	if(logSys !is null)
		logSys.lock.file.close();
}

/**
*	Prints message string in log file and in stdout if application is running
*	in not daemon mode. As argument is lazy, there is no overhead for logging
*	in rarely used code branches.
*
*	Also prints current time as an addition to the message.
*/
void logInfo(lazy string msg) nothrow
{
	scope(failure) {}
	logWithLevel("Info", stdout, msg);
}

/**
*	Prints message string in log file and in stderr if application is running
*	in not daemon mode. As argument is lazy, there is no overhead for logging
*	in rarely used code branches.
*
*	Also prints current time as an addition to the message.
*/
void logError(lazy string msg) nothrow
{
	scope(failure) {}
	logWithLevel("Error", stderr, msg);
}

private void logWithLevel(string level, File stream, lazy string msg)
{
	if(logSys is null || !logSys.lock.isSystemReady) return;
	
	auto fulMsg = level ~ " [" ~ Clock.currTime.toISOExtString ~ "]: " ~ msg;
	auto s = logSys.lock();
	s.file.write(fulMsg~'\n');
	if(!s.daemonMode) stream.writeln(fulMsg);
}

private class LogSystem
{
	FileStream file;
	bool daemonMode = false;

	private bool isSystemReady()
	{
		return file.isOpen && file.writable;
	}
}

private
{
	shared LogSystem logSys = null;
}

shared static ~this()
{
	shutdownLoggingSystem();
}

version(unittest)
{
	void testThread(std.concurrency.Tid owner, int i)
	{
		foreach(j; 1 .. 50)
		{
			logInfo(to!string(j));
			logError(to!string(j));
		}
		
		send(owner, true);
	}
}
unittest
{
	scope(exit)
	{
		shutdownLoggingSystem();
		if(exists(tempFileName))
			remove(tempFileName);
	}
	
	string tempFileName = buildPath(tempDir(), "logging_test.log"); 
	try
	{
		initLoggingSystem(tempFileName, true);
	} catch(Exception e)
	{
		assert(false, "Failed to init logging system: " ~ e.msg);
	}
	
	immutable n = 50;
	foreach(i; 1 .. n)
	{
		spawn(&testThread, thisTid, i);
	}
	
	auto t = TickDuration.currSystemTick + cast(TickDuration)dur!"seconds"(2);
	auto ni = 0;
	while(ni < n && t > TickDuration.currSystemTick) 
	{
		ni += 1;
	}
	assert(ni == n, "Concurrent logging test is failed!");
}