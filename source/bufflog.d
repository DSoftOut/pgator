// Copyright (с) 2013-2014 Gushcha Anton <ncrashed@gmail.com>
/*
* This file is part of Borey Engine.
*
* Boost Software License - Version 1.0 - August 17th, 2003
* 
* Permission is hereby granted, free of charge, to any person or organization
* obtaining a copy of the software and accompanying documentation covered by
* this license (the "Software") to use, reproduce, display, distribute,
* execute, and transmit the Software, and to prepare derivative works of the
* Software, and to permit third-parties to whom the Software is furnished to
* do so, all subject to the following:
* 
* The copyright notices in the Software and this entire statement, including
* the above license grant, this restriction and the following disclaimer,
* must be included in all copies of the Software, in whole or in part, and
* all derivative works of the Software, unless such copies or derivative
* works are solely in the form of machine-executable object code generated by
* a source language processor.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
* SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
* FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
* ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
* DEALINGS IN THE SOFTWARE.
*/
/**
*   Sometimes logging is needed only if something goes wrong. This module
*   describes a class-wrapper to handle delayed logging. 
*
*   Example:
*   ----------
*   auto delayed = new shared BufferedLogger(logger); // wrapping a logger
*	scope(exit) delayed.finalize(); // write down information in wrapped logger
*   scope(failure) delayed.minOutputLevel = LoggingLevel.Notice; // if failed, spam in console
*   delayed.logNotice("Hello!");
*
*   // do something that can fail
*
*   ----------
*/
module bufflog;

import std.array;
import std.stdio;
import stdlog;

/**
*   Class-wrapper around strict logger. All strings are written down
*   only after finalizing the wrapper.
*/
synchronized class BufferedLogger : CLogger
{
    this(shared ILogger delayLogger)
    {
        this.delayLogger = delayLogger;
        minOutputLevel = LoggingLevel.Muted;
    }
    
    override void rawInput(string message) @trusted
    {
        buffer ~= message;
    }
    
    override void finalize() @trusted
    {
        foreach(msg; buffer)
        {
            scope(failure) {}
            
            if(minOutputLevel != LoggingLevel.Muted)
                writeln(msg);
                
            delayLogger.rawInput(msg);
        }
    }
    
    shared ILogger delayLogger;
    string[] buffer;
}