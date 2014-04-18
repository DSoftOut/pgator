// Written in D programming language
/**
*    Part of asynchronous pool realization.
*    
*    Copyright: © 2014 DSoftOut
*    License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*    Authors: NCrashed <ncrashed@gmail.com>
*/
module db.async.workers.closed;

import dlogg.log;
import db.connection;
import db.async.workers.handler;
import std.container;
import std.typecons;
import std.concurrency;
import std.range;
import core.time;
import core.thread;

alias Tuple!(shared IConnection, "conn", TickDuration, "duration") TimedConnListElem;
alias DList!TimedConnListElem  TimedConnList;
   
static void closedChecker(shared ILogger logger, Duration reconnectTime)
{
    try 
    {
        setMaxMailboxSize(thisTid, 0, OnCrowding.block);
        Thread.getThis.isDaemon = true;
           
        TimedConnList list;
        auto ids = ThreadIds.receive();
        Tid exitTid;
           
        bool exit = false;
        while(!exit)
        {
            while (receiveTimeout(dur!"msecs"(1)
                , (Tid sender, bool v) 
                {
                    exit = v; 
                    exitTid = sender;
                }
                , (string com, shared(IConnection) conn, TickDuration time) 
                { 
                    if(com == "add")
                    {                 
                        list.insert(TimedConnListElem(conn, time));
                    }
                }
                , (Tid sender, string com) 
                {
                    if(com == "length")
                    {
                        sender.send(thisTid, list[].walkLength);
                    }
                }
                , (Variant v) { assert(false, "Unhandled message!"); }
            )) {}
               
            TimedConnList nextList;
            foreach(elem; list)
            {
                auto conn = elem.conn;
                auto time = elem.duration;

                if(TickDuration.currSystemTick > time)
                {
                    try
                    {
                        scope(success)
                        {
                            ids.connectingCheckerId.send("add", conn);
                        }
                           
                        conn.reconnect();      
                    } catch(ConnectException e)
                    {
                        logger.logDebug("Connection to server ",e.server," is still failing! Will retry over "
                            , reconnectTime.total!"seconds", ".", reconnectTime.fracSec.msecs, " seconds.");
                        elem.duration = TickDuration.currSystemTick + cast(TickDuration)reconnectTime;
                        nextList.insert(elem);
                    }
                } else
                {
                    nextList.insert(elem);
                } 
           }
           list.clear;  
           list = nextList;
        }
           
        scope(exit)
        {
            foreach(elem; list)
            {
                elem.conn.disconnect();
            } 
        }
        
        exitTid.send(true);
        logger.logDebug("Closed connections thread exited!");
    } catch (Throwable th)
    {
        logger.logError("AsyncPool: closed connections thread died!");
        logger.logError(text(th));
    }
}