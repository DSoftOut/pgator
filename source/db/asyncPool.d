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
    this(shared ILogger logger, shared(IConnection) delegate() connAllocator, Duration pReconnectTime, Duration pFreeConnTimeout)
    {
        this.logger = logger;
        allocateConnection = connAllocator;
        
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
            auto conn = allocateConnection();

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
        ids.freeCheckerId.send("length", thisTid);
        size_t freeCount = receiveOnly!size_t();
        ids.queringCheckerId.send("length", thisTid);
        size_t queringCount = receiveOnly!size_t();
        
        return freeCount + queringCount;
    }
    
    /**
    *    Returns current frozen connections number.
    */
    size_t inactiveConnections() @property
    {
        ids.closedCheckerId.send("length", thisTid);
        size_t closedCount = receiveOnly!size_t();
        ids.connectingCheckerId.send("length", thisTid);
        size_t connectingCount = receiveOnly!size_t();
        
        return closedCount + connectingCount;
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
       shared(IConnection) delegate() allocateConnection;
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
           TimedConnList list;
           auto ids = ThreadIds.receive();
           
           bool exit = false;
           while(!exit)
           {
               while (receiveTimeout(dur!"msecs"(1)
                   , (bool v) {exit = v;}
                   , (string com, shared IConnection conn, TickDuration time) {
                       if(com == "add")
                       {
                          list.insert(ElementType!TimedConnList(conn, time));
                       }}
                   , (string com, Tid sender) {
                       if(com == "length")
                       {
                           sender.send(list.length);
                       }
                   }
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
                   , (string com, Tid sender) {
                       if(com == "length")
                       {
                           sender.send(list.length);
                       }
                   }
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
                       
                           auto whenRetry = TickDuration.currSystemTick + cast(TickDuration)reconnectTime;
                           ids.closedCheckerId.send(ElementType!TimedConnList(conn, whenRetry));
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
           //scope(failure) {logError("AsyncPool: connecting thread died!");}
           try{
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
                   , (string com, Tid sender) {
                       if(com == "length")
                       {
                           sender.send(list.length);
                       }
                   }
               )) {}

               foreach(conn; list)
               {
                   logger.logInfo(text(conn.pollConnectionStatus()));
                   final switch(conn.pollConnectionStatus())
                   {
                       case ConnectionStatus.Pending:
                       {
                           continue;
                       }
                       case ConnectionStatus.Error:
                       {  
                           try conn.pollConnectionException();
                           catch(ConnectException e)
                           {
                               logger.logError(e.msg);
                               logger.logInfo("Will retry to connect to "~e.server~" over "~to!string(reconnectTime.seconds)~" seconds.");
                               
                               list.removeOne(conn);
                           
                               auto whenRetry = TickDuration.currSystemTick + cast(TickDuration)reconnectTime;
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
           } catch(Throwable ex) {writeln(ex);}
       }
       
       static void queringChecker(shared ILogger logger)
       {
           scope(failure) {logger.logError("AsyncPool: quering thread died!");}
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
                   , (string com, Tid sender) {
                       if(com == "length")
                       {
                           sender.send(list.length);
                       }
                   }
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

private void removeOne(T)(DList!T list, T elem)
{
   auto toRemove = list[].find(elem);
   list.remove(toRemove);
}

private size_t length(T)(DList!T list)
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
                    if(choose(0.01))
                    {
                        currConnStatus = ConnectionStatus.Error;
                    }
                }
            }
            writeln(currConnStatus);
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
}
unittest
{
    auto logger = new shared CLogger("asyncPool");
    auto pool = new AssyncPool(logger, (){return new shared TestConnection();}, dur!"msecs"(500), dur!"msecs"(500));
    pool.addServer("", 0);
    foreach(i; 0..5)
    {
        writeln("Pool active connections: ", pool.activeConnections);
        writeln("Pool inactive connections: ", pool.inactiveConnections);
        Thread.sleep(dur!"seconds"(1));
    }
    pool.finalize((){});
    logger.finalize();
}