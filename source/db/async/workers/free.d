// Written in D programming language
/**
*    Part of asynchronous pool realization.
*    
*    Copyright: © 2014 DSoftOut
*    License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*    Authors: NCrashed <ncrashed@gmail.com>
*/
module db.async.workers.free;

import dlogg.log;
import db.connection;
import db.async.workers.handler;
import std.container;
import std.concurrency;
import std.range;
import std.datetime;
import core.thread;
import util;

private alias DList!(shared IConnection) ConnectionList;
       
void freeChecker(shared ILogger logger, Duration reconnectTime, Duration aliveCheckTime)
{
    try 
    {
        setMaxMailboxSize(thisTid, 0, OnCrowding.block);
        Thread.getThis.isDaemon = true;
               
        DList!Tid connRequests;
        ConnectionList list;
        auto ids = ThreadIds.receive();
        Tid exitTid;
        auto nextCheckTime = Clock.currSystemTick + cast(TickDuration)aliveCheckTime;
                          
        bool exit = false;
        while(!exit)
        {
            while (receiveTimeout(dur!"msecs"(1)
                , (Tid sender, bool v) 
                {
                    exit = v; 
                    exitTid = sender;
                }
                , (string com, shared IConnection conn) 
                {
                    if(com == "add")
                    {
                        if(connRequests.empty) list.insert(conn);
                        else
                        {
                            auto reqTid = connRequests.front;
                            connRequests.removeFront;
                            reqTid.send(thisTid, conn); /// TODO: Check case the requester is already gone
                                                        /// then the conn is lost
                        }
                    }
                }
                , (Tid sender, string com) 
                {
                    if(com == "length")
                    {
                        sender.send(thisTid, list[].walkLength);
                    } else if(com == "get")
                    {
                        if(list.empty)
                        {
                            connRequests.insert(sender);
                        } else
                        {
                            sender.send(thisTid, list.front);
                            list.removeFront;
                        }
                        } else assert(false, "Invalid command!");
                    }
                    , (Variant v) { assert(false, "Unhandled message!"); }
            )) {}
            
            ConnectionList newList;     
            bool checkAlive = Clock.currSystemTick > nextCheckTime;
            foreach(conn; list)
            {
                void processFailedConn()
                {
                	static if (__VERSION__ < 2066) {
	                    logger.logInfo(text("Will retry to connect to server over "
	                        , reconnectTime.total!"seconds", ".", reconnectTime.fracSec.msecs, " seconds."));
                    } else {
	                    logger.logInfo(text("Will retry to connect to server over "
	                        , reconnectTime.total!"seconds", ".", reconnectTime.split!("seconds", "msecs").msecs, " seconds."));
                    }
                    
                    TickDuration whenRetry = TickDuration.currSystemTick + cast(TickDuration)reconnectTime;
                    ids.closedCheckerId.send("add", conn, whenRetry);
                }
                   
                if(conn.pollConnectionStatus == ConnectionStatus.Error)
                {
                    try conn.pollConnectionException();
                    catch(ConnectException e)
                    {
                        logger.logError(e.msg);
                        processFailedConn();
                        continue;
                    }
                }
                   
                if(checkAlive)
                {
                    if(!conn.testAlive)
                    {
                        logger.logError("Connection test on its aliveness is failed!");
                        processFailedConn();
                        continue;
                    }
                }
                
                newList.insert = conn;
            }
            list.clear;
            list = newList;
               
            if(checkAlive)
            {
                nextCheckTime = Clock.currSystemTick + cast(TickDuration)aliveCheckTime;
            }
        }
               
        // also compiler don't allow to put this in scope(exit)
        foreach(conn; list)
        {
            try
            {
                conn.disconnect();
            } 
            catch(Throwable e)
            {
                   
            }
        }
           
        exitTid.send(true);
        logger.logDebug("Free connections thread exited!");
    } catch (Throwable th)
    {
        logger.logError("AsyncPool: free connections thread died!");
        logger.logError(text(th));
    }
}