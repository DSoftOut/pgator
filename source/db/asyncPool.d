// Written in D programming language
/**
*    
*    Authors: NCrashed <ncrashed@gmail.com>
*/
module db.assyncPool;

import db.pool;
import db.connection;
import std.algorithm;
import std.container;
import std.concurrency;
import std.range;
import core.time;
import vibe.core.concurrency : lock;

/**
*    Describes asynchronous connection pool.
*/
class AssyncPool : IConnectionPool
{
    this(IConnection delegate() connAllocator, Duration pReconnectTime, Duration pFreeConnTimeout)
    {
        allocateConnection = connAllocator;
        
        closedConns     = new shared ConnectionList();
        connectingConns = new shared ConnectionList();
        freeConns       = new shared ConnectionList();
        queringConns    = new shared ConnectionList();
        
        mReconnectTime   = pReconnectTime;
        mFreeConnTimeout = pFreeConnTimeout;
        
        queringCheckerId    = spawn(&queringChecker, queringConns, freeConns);
        connectingCheckerId = spawn(&connectingChecker, connectingConns, freeConns, queringCheckerId);
        closedCheckerId     = spawn(&closedChecker, closedConns, connectingConns, connectingCheckerId);
    }
    
    /**
    *    Adds connection string to a SQL server with
    *    maximum connections count.
    *
    *    The pool will try to reconnect to the sql 
    *    server every $(B reconnectTime) is connection
    *    is dropped (or is down initially).
    */
    void addServer(string connString, size_t connNum)
    {
        auto conns = new IConnection[connNum];
        foreach(ref conn; conns)
        {
            conn = allocateConnection();
            conn.connect(connString);
        }
        connectingConns.lock.list.insertBack(conns);
    }
    
    /**
    *    If connection to a SQL server is down,
    *    the pool tries to reestablish it every
    *    time units returned by the method. 
    */
    Duration reconnectTime() @property
    {
        return mReconnectTime;
    }
    
    /**
    *    If there is no free connection for 
    *    specified duration while trying to
    *    initialize SQL query, then the pool
    *    throws $(B ConnTimeoutException) exception.
    */
    Duration freeConnTimeout() @property
    {
        return mFreeConnTimeout;
    }
    
    /**
    *    Returns current alive connections number.
    */
    size_t aliveConnections() @property
    {
        return freeConns.lock.list[].walkLength + queringConns.lock.list[].walkLength;
    }
    
    /**
    *    Awaits all queries to finish and then closes each connection.
    *    Calls $(B callback) when connections are closed.
    */
    void finalize(shared void delegate() callback)
    {
        closedCheckerId.send(true);
        connectingCheckerId.send(true);
        queringCheckerId.send(true, callback);
        finalized = true;
    }
    
    private
    {
       IConnection delegate() allocateConnection;
       Duration mReconnectTime;
       Duration mFreeConnTimeout;
       
       Tid closedCheckerId;
       Tid connectingCheckerId;
       Tid queringCheckerId;
       bool finalized = false;
       
       shared
       {
           ConnectionList closedConns;
           ConnectionList connectingConns;
           ConnectionList freeConns;
           ConnectionList queringConns;
       }
       
       static class ConnectionList
       {
           DList!IConnection list;
       }
       
       static void closedChecker( shared ConnectionList closedConns
                                , shared ConnectionList connectingConns
                                , Tid connectingCheckerId)
       {
           bool exit = false;
           while(!exit)
           {
               receiveTimeout(dur!"msecs"(1),
                   (bool v) {exit = v;}
               );
           }
           
           connectingCheckerId.send("done");
       }
       
       static void connectingChecker( shared ConnectionList connectingConns
                                    , shared ConnectionList freeConns
                                    , Tid queringCheckerId)
       {
           bool exit = false;
           while(!exit)
           {
               receiveTimeout(dur!"msecs"(1),
                   (bool v) {exit = v;}
               );
               {
                   auto cq = connectingConns.lock;
                   foreach(conn; cq.list)
                   {
                       final switch(conn.pollConnectionStatus())
                       {
                           case ConnectionStatus.Pending:
                           {
                               continue;
                           }
                           case ConnectionStatus.Error:
                           {
                               /// TODO: pass to special list with durations
                               /// don't forget to logg
                               break;
                           }
                           case ConnectionStatus.Finished:
                           {
                               auto toRemove = cq.list[].find(conn);
                               cq.list.remove(toRemove);
                               freeConns.lock.list.insert(conn);
                               break;
                           }
                       }
                   }
               }
           }
           
           queringCheckerId.send("done");
           auto val = receiveOnly!string();
           {
               auto conns = connectingConns.lock.list;
               foreach(conn; conns)
               {
                   conn.disconnect();
               } 
           }
       }
       
       static void queringChecker( shared ConnectionList queringConns
                                 , shared ConnectionList freeConns)
       {
           bool exit = false;
           void delegate() exitCallback;
           size_t last = queringConns.lock.list[].walkLength;
           while(!exit || last > 0)
           {
               receiveTimeout(dur!"msecs"(1),
                   (bool v, shared void delegate() callback) {exit = v; exitCallback = callback;}
               );
               {
                   auto qs = queringConns.lock;
                   foreach(conn; qs.list)
                   {
                       final switch(conn.pollQueringStatus())
                       {
                           case QueringStatus.Pending:
                           {
                               continue;
                           }
                           case QueringStatus.Error:
                           {
                               /// TODO: transfer error
                               break;
                           }
                           case QueringStatus.Finished:
                           {
                               /// TODO: transfer result
                               break;
                           }
                       }
                       auto toRemove = qs.list[].find(conn); 
                       qs.list.remove(toRemove);
                       freeConns.lock.list.insert(conn);
                   }
                   last = qs.list[].walkLength;
               }
           }
           
           auto val = receiveOnly!string();
           {
               auto conns = freeConns.lock.list;
               foreach(conn; conns)
               {
                   conn.disconnect();
               } 
           }
       }
    }
}