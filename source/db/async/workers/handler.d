// Written in D programming language
/**
*    Part of asynchronous pool realization.
*    
*    Copyright: © 2014 DSoftOut
*    License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*    Authors: NCrashed <ncrashed@gmail.com>
*/
module db.async.workers.handler;

import std.concurrency;
import dlogg.log;
import core.time;

/**
*   Struct-helper that holds all workers ids. It solves problem with
*   immutability for Tids and allows to send and receive messages in a batch.
*/
shared struct ThreadIds
{
    /// Worker for closed connections
    immutable Tid mClosedCheckerId;
    /// Worker for free connections
    immutable Tid mFreeCheckerId;
    /// Worker for connections in connecting state
    immutable Tid mConnectingCheckerId;
    /// Worker for quering
    immutable Tid mQueringCheckerId;
    
    /// Getter to cast away immutable
    Tid closedCheckerId()
    {
        return cast()mClosedCheckerId;
    }
    
    /// Getter to cast away immutable
    Tid freeCheckerId()
    {
        return cast()mFreeCheckerId;
    }
    
    /// Getter to cast away immutable
    Tid connectingCheckerId()
    {
        return cast()mConnectingCheckerId;
    }
    
    /// Getter to cast away immutable
    Tid queringCheckerId()
    {
        return cast()mQueringCheckerId;
    }
    
    /// Creating handler with all workers ids
    this(Tid closedCheckerId, Tid freeCheckerId, Tid connectingCheckerId, Tid queringCheckerId)
    {
        this.mClosedCheckerId     = cast(immutable)closedCheckerId;
        this.mFreeCheckerId       = cast(immutable)freeCheckerId;
        this.mConnectingCheckerId = cast(immutable)connectingCheckerId;
        this.mQueringCheckerId    = cast(immutable)queringCheckerId;
    }
    
    /**
    *   Sends itself to all workers. Worker can restore local handler
    *   with use fo $(B receive) method.
    */
    void sendTids()
    {
        sendTo(closedCheckerId);
        sendTo(freeCheckerId);
        sendTo(connectingCheckerId);
        sendTo(queringCheckerId);
    }
    
    /**
    *   Sending content of the handler to specified $(B dist)
    *   thread. There it can restore the handler with $(B receive) 
    *   method.
    */   
    private void sendTo(Tid dist)
    {
        dist.send(closedCheckerId);
        dist.send(freeCheckerId);
        dist.send(connectingCheckerId);
        dist.send(queringCheckerId);
    }
    
    /**
    *   Constructing handler from message mailbox.
    *   The method is used with $(B sendTids) in
    *   workers. 
    */  
    static shared(ThreadIds) receive()
    {
        auto closedTid = receiveOnly!Tid();
        auto freeTid = receiveOnly!Tid();
        auto connectingTid = receiveOnly!Tid();
        auto queringTid = receiveOnly!Tid();
        return shared ThreadIds(closedTid, freeTid, connectingTid, queringTid);
    }
     
    /**
    *   Asks all workers to quit.
    */   
    void finalize(shared ILogger logger)
    {
        void finalizeThread(Tid tid, string name)
        {
            tid.send(thisTid, true);
            if(!receiveTimeout(dur!"seconds"(1), (bool val) {}))
            {
                logger.logDebug(name, " thread refused to terminated safely!");
            }
        }
       
        finalizeThread(closedCheckerId, "Closed connections");
        finalizeThread(freeCheckerId, "Free connections");
        finalizeThread(connectingCheckerId, "Connecting connections");
        finalizeThread(queringCheckerId, "Quering connections");
    }
}