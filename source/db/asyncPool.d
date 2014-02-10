// Written in D programming language
/**
*    
*    Authors: NCrashed <ncrashed@gmail.com>
*/
module db.assyncPool;

import log;
import db.pool;
import db.connection;
import std.algorithm;
import std.conv;
import std.container;
import std.concurrency;
import std.range;
import std.typecons;
import core.time;

/**
*    Describes asynchronous connection pool.
*/
class AssyncPool : IConnectionPool
{
    this(shared ILogger logger, IConnectionProvider provider, Duration pReconnectTime, Duration pFreeConnTimeout)
    {
        this.logger = logger;
        this.provider = provider;

        mReconnectTime   = pReconnectTime;
        mFreeConnTimeout = pFreeConnTimeout;      
        
        ids = ThreadIds(  spawn(&closedChecker, logger)
                        , spawn(&freeChecker, logger, reconnectTime)
                        , spawn(&connectingChecker, logger, reconnectTime)
                        , spawn(&queringChecker, logger));

        ids.sendTids;
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
        TimedConnList failedList;
        ConnectionList connsList;
        foreach(i; 0..connNum)
        {
            auto conn = provider.allocate;

            bool failed = false;
            try
            {
                conn.connect(connString);
            }
            catch(ConnectException e)
            {
                failed = true;
                logger.logError(e.msg);
                logger.logInfo("Will retry to connect to "~e.server~" over "~to!string(reconnectTime.seconds)~" seconds.");
               
                auto whenRetry = TickDuration.currSystemTick + cast(TickDuration)reconnectTime;
                failedList.insert(ElementType!TimedConnList(conn, whenRetry));
            }
            
            if(!failed) connsList.insert(conn);
        }

        foreach(conn; connsList)
            ids.connectingCheckerId.send("add", conn);
        foreach(elem; failedList)
            ids.closedCheckerId.send("add", elem[0], elem[1]);
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
    size_t activeConnections() @property
    {
        size_t freeCount, queringCount;
        ids.freeCheckerId.send(thisTid, "length");
        ids.queringCheckerId.send(thisTid, "length");
        
        foreach(i;0..2)
            receive((Tid sender, size_t answer) 
                {
                    if(sender == ids.freeCheckerId)
                        freeCount = answer;
                    else if(sender == ids.queringCheckerId)
                        queringCount = answer;
                }
            );

        return freeCount + queringCount;
    }
    
    /**
    *    Returns current frozen connections number.
    */
    size_t inactiveConnections() @property
    {
        size_t closedCount, connectingCount;
        ids.closedCheckerId.send(thisTid, "length");
        ids.connectingCheckerId.send(thisTid, "length");
        
        foreach(i;0..2)
            receive((Tid sender, size_t answer) 
                {
                    if(sender == ids.closedCheckerId)
                        closedCount = answer;
                    else if(sender == ids.connectingCheckerId)
                        connectingCount = answer;
                }
            );
        
        return closedCount + connectingCount;
    }
    
    size_t totalConnections() @property
    {
        size_t freeCount, queringCount;
        size_t closedCount, connectingCount;
        ids.freeCheckerId.send(thisTid, "length");
        ids.queringCheckerId.send(thisTid, "length");
        ids.closedCheckerId.send(thisTid, "length");
        ids.connectingCheckerId.send(thisTid, "length");
        
        foreach(i;0..4)
            receive((Tid sender, size_t answer) 
                {
                    if(sender == ids.freeCheckerId)
                        freeCount = answer;
                    else if(sender == ids.queringCheckerId)
                        queringCount = answer;
                    else if(sender == ids.closedCheckerId)
                        closedCount = answer;
                    else if(sender == ids.connectingCheckerId)
                        connectingCount = answer;
                }
            );
        
        return freeCount + queringCount + closedCount + connectingCount;
    }
    
    /**
    *    Awaits all queries to finish and then closes each connection.
    *    Calls $(B callback) when connections are closed.
    */
    void finalize(shared void delegate() callback)
    {
        ids.finalize(callback);
        finalized = true;
    }
    
    private
    {
       shared ILogger logger;
       IConnectionProvider provider;
       Duration mReconnectTime;
       Duration mFreeConnTimeout;
       
       struct ThreadIds
       {
           Tid closedCheckerId;
           Tid freeCheckerId;
           Tid connectingCheckerId;
           Tid queringCheckerId;
           
           void sendTids()
           {
               sendTo(closedCheckerId);
               sendTo(freeCheckerId);
               sendTo(connectingCheckerId);
               sendTo(queringCheckerId);
           }
           
           private void sendTo(Tid dist)
           {
               dist.send(closedCheckerId);
               dist.send(freeCheckerId);
               dist.send(connectingCheckerId);
               dist.send(queringCheckerId);
           }
           
           static ThreadIds receive()
           {
               auto closedTid = receiveOnly!Tid();
               auto freeTid = receiveOnly!Tid();
               auto connectingTid = receiveOnly!Tid();
               auto queringTid = receiveOnly!Tid();
               return ThreadIds(closedTid, freeTid, connectingTid, queringTid);
           }
           
           void finalize(shared void delegate() callback)
           {
               closedCheckerId.send(true);
               freeCheckerId.send(true);
               connectingCheckerId.send(true);
               queringCheckerId.send(true, callback);
           }
       }
       ThreadIds ids;
       bool finalized = false;
       
       alias DList!(shared IConnection) ConnectionList;
       alias DList!(Tuple!(shared IConnection, TickDuration)) TimedConnList;
       
       static void closedChecker(shared ILogger logger)
       {
           scope(failure) {logger.logError("AsyncPool: closed connections thread died!");}
           setMaxMailboxSize(thisTid, 0, OnCrowding.block);
           
           TimedConnList list;
           auto ids = ThreadIds.receive();
           
           bool exit = false;
           while(!exit)
           {
               while (receiveTimeout(dur!"msecs"(1)
                   , (bool v) {exit = v;}
                   , (string com, shared(IConnection) conn, TickDuration time) { 
                       if(com == "add")
                       {
                          list.insert(ElementType!TimedConnList(conn, time));
                       }}
                   , (Tid sender, string com) {
                       if(com == "length")
                       {
                           sender.send(thisTid, list.length);
                       }
                   }
                   , (Variant v) { assert(false, "Unhandled message!"); }
               )) {}
               
               foreach(elem; list)
               {
                   auto conn = elem[0];
                   auto time = elem[1];
                   
                   if(TickDuration.currSystemTick > time)
                   {
                       list.removeOne(elem);
                       ids.connectingCheckerId.send("add", conn);
                   }
               }  
           }
           
           writeln("1 closed");
       }
       
       static void freeChecker(shared ILogger logger, Duration reconnectTime)
       {
           scope(failure) {logger.logError("AsyncPool: free connections thread died!");}
           setMaxMailboxSize(thisTid, 0, OnCrowding.block);
           
           ConnectionList list;
           auto ids = ThreadIds.receive();
                      
           bool exit = false;
           while(!exit)
           {
               while (receiveTimeout(dur!"msecs"(1)
                   , (bool v) {exit = v;}
                   , (string com, shared IConnection conn) {
                       if(com == "add")
                       {
                          list.insert(conn);
                       }}
                   , (Tid sender, string com) {
                       if(com == "length")
                       {
                           sender.send(thisTid, list.length);
                       }
                   }
                   , (Variant v) { assert(false, "Unhandled message!"); }
               )) {}
               
               foreach(conn; list)
               {
                   if(conn.pollConnectionStatus == ConnectionStatus.Error)
                   {
                       try conn.pollConnectionException();
                       catch(ConnectException e)
                       {
                           logger.logError(e.msg);
                           logger.logInfo("Will retry to connect to "~e.server~" over "~to!string(reconnectTime.seconds)~" seconds.");
                           
                           list.removeOne(conn);
                       
                           TickDuration whenRetry = TickDuration.currSystemTick + cast(TickDuration)reconnectTime;
                           ids.closedCheckerId.send(conn, whenRetry);
                       }
                   }
               }
           }
           
           foreach(conn; list)
           {
               conn.disconnect();
           } 
           writeln("2 closed");
       }
       
       static void connectingChecker(shared ILogger logger, Duration reconnectTime)
       {
           scope(failure) {logger.logError("AsyncPool: connecting thread died!");}
           setMaxMailboxSize(thisTid, 0, OnCrowding.block);
           
           ConnectionList list;
           auto ids = ThreadIds.receive();
           
           bool exit = false;
           while(!exit)
           {
               while(receiveTimeout(dur!"msecs"(1)
                   , (bool v) {exit = v;}
                   , (string com, shared IConnection conn) {
                       if(com == "add")
                       {
                          list.insert(conn);
                       }}
                   , (Tid sender, string com) {
                       if(com == "length")
                       {
                           sender.send(thisTid, list.length);
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
                               logger.logInfo("Will retry to connect to "~e.server~" over "~to!string(reconnectTime.seconds)~" seconds.");
                               
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

           foreach(conn; list)
           {
               conn.disconnect();
           } 
           
           writeln("3 closed");
       }
       
       static void queringChecker(shared ILogger logger)
       {
           scope(failure) {logger.logError("AsyncPool: quering thread died!");}
           setMaxMailboxSize(thisTid, 0, OnCrowding.block);
           
           ConnectionList list;
           auto ids = ThreadIds.receive();
          
           bool exit = false;
           void delegate() exitCallback;
           size_t last = list[].walkLength;
           while(!exit || last > 0)
           {
               while(receiveTimeout(dur!"msecs"(1)
                   , (bool v, shared void delegate() callback) {
                       exit = v; 
                       exitCallback = callback;}
                   , (string com, shared IConnection conn) {
                       if(com == "add")
                       {
                          list.insert(conn);
                       }}
                   , (Tid sender, string com) {
                       if(com == "length")
                       {
                           sender.send(thisTid, list.length);
                       }
                   }
                   , (Variant v) { assert(false, "Unhandled message!"); }
               )) {}
               
               foreach(conn; list)
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
                   
                   list.removeOne(conn);
                   ids.freeCheckerId.send("add", conn);
               }
               last = list.length;
           }

           exitCallback();
           writeln("4 closed");
       }
    }
}

private void removeOne(T)(ref DList!T list, T elem)
{
   auto toRemove = list[].find(elem).take(1);
   list.linearRemove(toRemove);
}

private size_t length(T)(ref DList!T list)
{
    return list[].walkLength;
}

version(unittest)
{
    import std.stdio;
    import std.random;
    import core.thread;
    import stdlog;
    
    bool choose(float chance)
    {
        return uniform!"[]"(0.0,1.0) < chance;
    }
    
    synchronized class TestConnection : IConnection
    {
        this()
        {
            currConnStatus = ConnectionStatus.Pending;
            currQueringStatus = QueringStatus.Finished;
        }
        
        void connect(string connString)
        {
            if(choose(0.1))
            {
                throw new ConnectException("", "Test connection is failed!");
            } 
            currConnStatus = ConnectionStatus.Pending;
        }
        
        ConnectionStatus pollConnectionStatus()
        {
            final switch(currConnStatus)
            {
                case ConnectionStatus.Pending:
                {
                    if(choose(0.3))
                    {
                        currConnStatus = ConnectionStatus.Finished;
                    } else if (choose(0.1))
                    {
                        currConnStatus = ConnectionStatus.Error;
                    }
                    break;
                }
                case ConnectionStatus.Error:
                {
                    break;
                }
                case ConnectionStatus.Finished:
                {
                    break;
                }
            }
            return currConnStatus;
        }
        
        void pollConnectionException()
        {
            throw new ConnectException("", "Test connection is failed!");
        }

        QueringStatus pollQueringStatus()
        {
           final switch(currQueringStatus)
            {
                case QueringStatus.Pending:
                {
                    if(choose(0.3))
                    {
                        currQueringStatus = QueringStatus.Finished;
                    } else if (choose(0.1))
                    {
                        currQueringStatus = QueringStatus.Error;
                    }
                    break;
                }
                case QueringStatus.Error:
                {
                    break;
                }
                case QueringStatus.Finished:
                {
                    if(choose(0.01))
                    {
                        currQueringStatus = QueringStatus.Error;
                    }
                }
            }
            return currQueringStatus;
        } 

        void pollQueryException()
        {
            throw new QueryException("Test query is failed!");
        }
        
        void disconnect() nothrow
        {
            currConnStatus = ConnectionStatus.Error;
        }
        
        private ConnectionStatus currConnStatus;
        private QueringStatus currQueringStatus;
    }
    
    class TestConnProvider : IConnectionProvider
    {
        shared(IConnection) allocate()
        {
            return new shared TestConnection();
        }
    }
}
unittest
{
    auto logger = new shared CLogger("asyncPool");
    auto pool = new AssyncPool(logger, new TestConnProvider(), dur!"seconds"(1), dur!"seconds"(1));
    
    immutable n = 10;
    pool.addServer("noserver", n);
    foreach(i; 0..5)
    {
        auto active = pool.activeConnections;
        auto inactive = pool.inactiveConnections;
        auto total = pool.totalConnections;
        writeln("Pool active connections: ", pool.activeConnections);
        writeln("Pool inactive connections: ", pool.inactiveConnections);
        assert(active + inactive == total);
        assert(total == n);
        Thread.sleep(dur!"seconds"(1));
    }
    pool.finalize((){});
    logger.finalize();
}