// Written in D programming language
/**
*    Part of asynchronous pool realization.
*    
*    Copyright: © 2014 DSoftOut
*    License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*    Authors: NCrashed <ncrashed@gmail.com>
*/
module db.async.workers.connecting;

import dlogg.log;
import db.connection;
import db.async.workers.handler;
import std.algorithm;
import std.container;
import std.concurrency;
import std.datetime;
import std.range;
import core.thread;
import util;

private alias DList!(shared IConnection) ConnectionList;

void connectingChecker(shared ILogger logger, Duration reconnectTime)
{
    try
    {
        setMaxMailboxSize(thisTid, 0, OnCrowding.block);
        Thread.getThis.isDaemon = true;
           
        ConnectionList list;
        auto ids = ThreadIds.receive();
        Tid exitTid;
           
        bool exit = false;
        while(!exit)
        {
            while(receiveTimeout(dur!"msecs"(1)
                , (Tid sender, bool v) 
                {
                    exit = v; 
                    exitTid = sender;
                }
                , (string com, shared IConnection conn) 
                {
                    if(com == "add")
                    {
                        list.insert(conn);
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

            foreach(conn; list)
            {
                final switch(conn.pollConnectionStatus())
                {
                    case ConnectionStatus.Pending:
                    {
                        break;
                    }
                    case ConnectionStatus.Error:
                    {  
                        try conn.pollConnectionException();
                        catch(ConnectException e)
                        {
                            logger.logError(e.msg);
			                static if (__VERSION__ < 2066) {
				                logger.logDebug("Will retry to connect to ", e.server, " over "
				                       , reconnectTime.total!"seconds", ".", reconnectTime.fracSec.msecs, " seconds.");
			                } else {
				                logger.logDebug("Will retry to connect to ", e.server, " over "
				                       , reconnectTime.total!"seconds", ".", reconnectTime.split!("seconds", "msecs").msecs, " seconds.");
			                }
                            list.removeOne(conn);
                           
                            TickDuration whenRetry = TickDuration.currSystemTick + cast(TickDuration)reconnectTime;
                            ids.closedCheckerId.send("add", conn, whenRetry);
                        }
                        break;
                    }
                    case ConnectionStatus.Finished:
                    {
                        list.removeOne(conn);
                        ids.freeCheckerId.send("add", conn);
                        break;
                    }
                }
            }
        }

        scope(exit)
        {
            foreach(conn; list)
            {
                conn.disconnect();
            } 
        }
           
        exitTid.send(true);
        logger.logDebug("Connecting thread exited!");
    } catch (Throwable th)
    {
        logger.logError("AsyncPool: connecting thread died!");
        logger.logError(text(th));
    }
}