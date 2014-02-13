// Written in D programming language
/**
*    
*    Authors: NCrashed <ncrashed@gmail.com>
*/
module db.assyncPool;

import log;
import db.pool;
import db.connection;
import db.pq.api;
import std.algorithm;
import std.conv;
import std.container;
import std.concurrency;
import std.exception;
import std.range;
import std.typecons;
import core.time;
import core.thread;
import vibe.core.core;
    
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
        
        ids = ThreadIds(  spawn(&closedChecker, logger, reconnectTime)
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
                failedList.insert(TimedConnListElem(conn, whenRetry));
            }
            
            if(!failed) connsList.insert(conn);
        }

        foreach(conn; connsList)
            ids.connectingCheckerId.send("add", conn);
        foreach(elem; failedList)
            ids.closedCheckerId.send("add", elem.conn, elem.duration);
    }
    
    protected synchronized static class Query : IQuery
    {
        this(string command, string[] params)
        {
            this.command = command;
            this.params = params.dup;
        }
        
        bool opEqual(Object o)
        {
            auto b = cast(Query)o;
            if(b is null) return false;
            
            return command == b.command && params == b.params;
        }
        
        immutable string command;
        immutable string[] params;
    }
    
    /**
    *   Synchronous blocking way to execute query.
    *   Throws: ConnTimeoutException, QueryProcessingException
    */
    InputRange!(shared IPGresult) execQuery(string command, string[] params)
    {
        auto query = postQuery(command, params);
        while(!isQueryReady(query)) yield;
        return getQuery(query);
    }
    
    /**
    *   Asynchronous way to execute query. User can check
    *   query status by calling $(B isQueryReady) method.
    *   When $(B isQueryReady) method returns true, the
    *   query can be finalized by $(B getQuery) method.
    * 
    *   Returns: Specific interface to distinct the query
    *            among others.
    *   See_Also: isQueryReady, getQuery.
    *   Throws: ConnTimeoutException
    */
    shared(IQuery) postQuery(string command, string[] params)
    {
        auto conn = fetchFreeConnection();
        auto query = new shared Query(command, params);
        processingQueries.insert(query);
        
        ids.queringCheckerId.send(thisTid, conn, query);
        
        return query;
    }
    
    /**
    *   Returns true if query processing is finished (doesn't
    *   matter the actual reason, error or query object is invalid,
    *   or successful completion).
    *
    *   If the method returns true, then $(B getQuery) method
    *   can be called in non-blocking manner.
    *
    *   See_Also: postQuery, getQuery.
    */
    bool isQueryReady(shared IQuery query) nothrow
    {
        scope(failure) return true;
        
        if(processingQueries[].find(query).empty)
            return true;
            
        fetchResponds();
        
        if(query in awaitingResponds) return true;
        else return false;
    }
    
    private void fetchResponds()
    {
        receiveTimeout(dur!"msecs"(1),
            (Tid tid, shared IQuery query, Respond respond)
            {
                assert(query !in awaitingResponds);
                awaitingResponds[query] = respond;
            }
        );
    }
    
    /**
    *   Retrieves SQL result from specified query.
    *   
    *   If previously called $(B isQueryReady) returns true,
    *   then the method is not blocking, else it falls back
    *   to $(B execQuery) behave.
    *
    *   See_Also: postQuery, isQueryReady
    *   Throws: UnknownQueryException, QueryProcessingException
    */
    InputRange!(shared IPGresult) getQuery(shared IQuery query)
    {
        if(processingQueries[].find(query).empty)
            throw new UnknownQueryException();
             
        if(query in awaitingResponds) 
        {
            processingQueries.removeOne(query);
            auto respond = awaitingResponds[query];
            if(respond.failed)
                throw new QueryProcessingException(respond.exception.msg);
            else
                return respond.result[].inputRangeObject;
        } else
        {
            while(!isQueryReady(query)) yield;
            return getQuery(query);
        }
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
            enforce(receiveTimeout(dur!"seconds"(1),
                (Tid sender, size_t answer) 
                {
                    if(sender == ids.closedCheckerId)
                        closedCount = answer;
                    else if(sender == ids.connectingCheckerId)
                        connectingCount = answer;
                }
            ), "Async pool internal problem! Workers don't respond!");
        
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
            enforce(receiveTimeout(dur!"seconds"(1),
                (Tid sender, size_t answer) 
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
            ), "Async pool internal problem! Workers don't respond!");
        
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
    
    /**
    *   Returns first free connection from the pool.
    *   Throws: ConnTimeoutException
    */
    protected shared(IConnection) fetchFreeConnection()
    {
        ids.freeCheckerId.send(thisTid, "get");
        shared IConnection res;
        enforceEx!ConnTimeoutException(receiveTimeout(freeConnTimeout,
                (Tid sender, shared IConnection conn) 
                {
                    res = conn;
                }
            ));
        return res;
    }
    
    private
    {
       shared ILogger logger;
       DList!(shared IQuery) processingQueries;
       Respond[shared IQuery] awaitingResponds;
       IConnectionProvider provider;
       Duration mReconnectTime;
       Duration mFreeConnTimeout;
       
       /// Worker returns this as query result
       struct Respond
       {
           this(QueryException e)
           {
               failed = true;
               exception = e;
           }
           
           this(DList!(shared IPGresult) result)
           {
               failed = false;
               this.result = result;
           }
           
           bool failed;
           __gshared QueryException exception;
           __gshared DList!(shared IPGresult) result;
       }
       
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
               
               bool exit = false;
               while(!exit)
               {
                   while (receiveTimeout(dur!"msecs"(1)
                       , (bool v) {exit = v;}
                       , (string com, shared(IConnection) conn, TickDuration time) { 
                           if(com == "add")
                           {
                              list.insert(TimedConnListElem(conn, time));
                           }}
                       , (Tid sender, string com) {
                           if(com == "length")
                           {
                               sender.send(thisTid, list.length);
                           }
                       }
                       , (Variant v) { assert(false, "Unhandled message!"); }
                   )) {}
                   
                   foreach(ref elem; list)
                   {
                       auto conn = elem.conn;
                       auto time = elem.duration;
                       
                       if(TickDuration.currSystemTick > time)
                       {
                           try
                           {
                               scope(success)
                               {
                                   list.removeOne(elem);
                                   ids.connectingCheckerId.send("add", conn);
                               }
                               conn.reconnect();      
                           } catch(ConnectException e)
                           {
                               logger.logInfo("Connection to server "~e.server~" is still failing! Will retry over "
                                   ~to!string(reconnectTime.seconds)~" seconds.");
                               elem.duration = TickDuration.currSystemTick + cast(TickDuration)reconnectTime; 
                           }
                       }
                   }  
               }
               
               scope(exit)
               {
                   foreach(elem; list)
                   {
                       elem.conn.disconnect();
                   } 
               }
           
           } catch (Throwable th)
           {
               logger.logError("AsyncPool: closed connections thread died!");
               logger.logError(text(th));
           }
       }
       
       static void freeChecker(shared ILogger logger, Duration reconnectTime)
       {
           try 
           {
               setMaxMailboxSize(thisTid, 0, OnCrowding.block);
               Thread.getThis.isDaemon = true;
               
               DList!Tid connRequests;
               ConnectionList list;
               auto ids = ThreadIds.receive();
                          
               bool exit = false;
               while(!exit)
               {
                   while (receiveTimeout(dur!"msecs"(1)
                       , (bool v) {exit = v;}
                       , (string com, shared IConnection conn) 
                       {
                           if(com == "add")
                           {
                               if(connRequests.empty) list.insert(conn);
                               else
                               {
                                   auto reqTid = connRequests.front;
                                   connRequests.removeFront;
                                   reqTid.send(thisTid, conn);
                               }
                           }
                       }
                       , (Tid sender, string com) {
                           if(com == "length")
                           {
                               sender.send(thisTid, list.length);
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
                               ids.closedCheckerId.send("add", conn, whenRetry);
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
           
           } catch (Throwable th)
           {
               logger.logError("AsyncPool: free connections thread died!");
               logger.logError(text(th));
           }
       }
       
       static void connectingChecker(shared ILogger logger, Duration reconnectTime)
       {
           try
           {
               setMaxMailboxSize(thisTid, 0, OnCrowding.block);
               Thread.getThis.isDaemon = true;
               
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
    
               scope(exit)
               {
                   foreach(conn; list)
                   {
                       conn.disconnect();
                   } 
               }
           } catch (Throwable th)
           {
               logger.logError("AsyncPool: connecting thread died!");
               logger.logError(text(th));
           }
       }
       
       alias Tuple!(Tid, "sender", shared IConnection, "conn", shared IQuery, "query") QueryConnListElem;
       alias DList!QueryConnListElem QueryConnList;
       
       static void queringChecker(shared ILogger logger)
       {
           try
           {
               setMaxMailboxSize(thisTid, 0, OnCrowding.block);
               Thread.getThis.isDaemon = true;
               
               QueryConnList list;
               auto ids = ThreadIds.receive();
              
               bool exit = false;
               void delegate() exitCallback;
               size_t last = list[].walkLength;
               while(!exit || last > 0)
               {
                   while(receiveTimeout(dur!"msecs"(1)
                       , (bool v, shared void delegate() callback) 
                           {
                               exit = v; 
                               exitCallback = callback;
                           }
                       , (Tid sender, shared IConnection conn, shared Query query) 
                           {
                               bool failed = false;
                               try conn.postQuery(query.command.dup, query.params.dup);
                               catch (QueryException e)
                               {
                                  failed = true;
                                  sender.send(thisTid, cast(shared IQuery)query, Respond(e));
                               }
                               if(!failed)
                                   list.insert(QueryConnListElem(sender, conn, query));
                           }
                       , (Tid sender, string com) 
                           {
                               if(com == "length")
                               {
                                   sender.send(thisTid, list.length);
                               }
                           }
                       , (Variant v) { assert(false, "Unhandled message!"); }
                   )) {}
                   
                   foreach(elem; list)
                   {
                       Tid sender = elem.sender;
                       auto conn = elem.conn;
                       auto query = elem.query;
                       
                       final switch(conn.pollQueringStatus())
                       {
                           case QueringStatus.Pending:
                           {
                               continue;
                           }
                           case QueringStatus.Error:
                           {
                               try conn.pollQueryException();
                               catch(QueryException e)
                               {
                                   sender.send(thisTid, query, Respond(e));
                               } 
                               break;
                           }
                           case QueringStatus.Finished:
                           {
                               try sender.send(thisTid, query, Respond(conn.getQueryResult));
                               catch(QueryException e)
                               {
                                   sender.send(thisTid, query, Respond(e));
                               } 
                               break;
                           }
                       }
                       
                       list.removeOne(elem);
                       if(exit) conn.disconnect();
                       else ids.freeCheckerId.send("add", conn);
                   }
                   last = list.length;
               }
    
               exitCallback();
           } catch (Throwable th)
           {
               logger.logError("AsyncPool: quering thread died!");
               logger.logError(text(th));
           }
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
    import dunit.mockable;
    
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
            currConnStatus = ConnectionStatus.Pending;
        }
        
        void reconnect()
        {
            connect("");
        }
        
        ConnectionStatus pollConnectionStatus()
        {
            return currConnStatus;
        }
        
        void pollConnectionException()
        {
            throw new ConnectException("", "Test connection is failed!");
        }

        QueringStatus pollQueringStatus()
        {
//           final switch(currQueringStatus)
//            {
//                case QueringStatus.Pending:
//                {
//                    if(choose(0.3))
//                    {
//                        currQueringStatus = QueringStatus.Finished;
//                    } else if (choose(0.1))
//                    {
//                        currQueringStatus = QueringStatus.Error;
//                    }
//                    break;
//                }
//                case QueringStatus.Error:
//                {
//                    break;
//                }
//                case QueringStatus.Finished:
//                {
//                    if(choose(0.01))
//                    {
//                        currQueringStatus = QueringStatus.Error;
//                    }
//                }
//            }
            return currQueringStatus;
        } 

        void pollQueryException()
        {
            throw new QueryException("Test query is failed!");
        }
        
        DList!(shared IPGresult) getQueryResult()
        {
            assert(false, "Not used!"); ///TODO: fix when you are adding query unittests
        }
        
        void postQuery(string com, string[] params)
        {
            assert(false, "Not used!"); ///TODO: fix when you are adding query unittests
        }
        
        void disconnect() nothrow
        {
            currConnStatus = ConnectionStatus.Error;
        }
        
        string server() const nothrow
        {
            return "";
        }

        
        protected ConnectionStatus currConnStatus;
        protected QueringStatus currQueringStatus;
        
        mixin Mockable!TestConnection;
    }
}
/**
*   Testing connection process. Some connections can fail and then they should be reconnected again.
*/
unittest
{
    write("Testing async pool. Connection fail immediately... ");
    scope(success) writeln("Finished!");
    scope(failure) writeln("Failed!");
    
    auto logger = new shared CLogger("asyncPool.unittest2");
    scope(exit) logger.finalize();
    logger.minOutputLevel = LoggingLevel.Muted;
    
    synchronized class ConnectionCheckConn : TestConnection
    {
        this(bool fail)
        {
            this.fail = fail;
        }
        
        override void connect(string connString)
        {
            if(fail)
                throw new ConnectException("", "Test fail");
        }
        
        override void reconnect()
        {
            if(fail)
                throw new ReconnectException("");
        }
        
        override ConnectionStatus pollConnectionStatus()
        {
            return fail ? ConnectionStatus.Error : ConnectionStatus.Finished;
        }
        
        private bool fail;
    }
    immutable succConns = 18;
    immutable failConns = 12;
    immutable n = succConns + failConns;
    auto provider = new class IConnectionProvider {
        override shared(IConnection) allocate()
        {
            if(succs < succConns)
            {
                succs++;
                return new shared ConnectionCheckConn(false);
            } else if(fails < failConns)
            {
                fails++;
                return new shared ConnectionCheckConn(true);
            }
            assert(0);
        }
        
        private uint succs, fails;
    };
   
    auto pool = new AssyncPool(logger, cast(IConnectionProvider)provider, dur!"msecs"(500), dur!"msecs"(500));
    scope(exit) pool.finalize((){});
    pool.addServer("noserver", n);
    
    auto active = pool.activeConnections;
    auto inactive = pool.inactiveConnections;
    auto total = pool.totalConnections;
    
    assert(active + inactive == total, text("Total connections count != active + inactive. ", total, "!=", active,"+",inactive));
    assert(total == n, text("Some connections are lost! ", total, "!=", n));

    Thread.sleep(dur!"seconds"(1));

    active = pool.activeConnections;
    inactive = pool.inactiveConnections;
    total = pool.totalConnections;

    assert(active + inactive == total, text("Total connections count != active + inactive. ", total, "!=", active,"+",inactive));
    assert(total == n, text("Some connections are lost! ", total, "!=", n));
    assert(active == succConns, text("Active connections != succeed connections. ", active,"!=", succConns));
    assert(inactive == failConns, text("Inactive connections != failed connections. ", inactive,"!=", failConns));
}
/**
*   Testing connection process. Some connections can fail while connecting.
*/
unittest
{
    write("Testing async pool. Connection fail while connecting... ");
    scope(success) writeln("Finished!");
    scope(failure) writeln("Failed!");
    
    auto logger = new shared CLogger("asyncPool.unittest1");
    scope(exit) logger.finalize();
    logger.minOutputLevel = LoggingLevel.Muted;
    
    synchronized class ConnectionCheckConn : TestConnection
    {
        this(uint ticks, uint failAfter)
        {
            this.ticks = ticks;
            this.failAfter = failAfter;
        }
        
        override ConnectionStatus pollConnectionStatus()
        {
            if(currConnStatus == ConnectionStatus.Pending)
            {
                if(currTicks > ticks) 
                {
                    currConnStatus = ConnectionStatus.Finished;
                } else if (currTicks > failAfter)
                {
                    currConnStatus = ConnectionStatus.Error;
                }
            }
            currTicks++;
            return super.pollConnectionStatus();
        }
        
        private uint currTicks;
        private uint ticks, failAfter;
    }
    immutable succConns = 18;
    immutable failConns = 12;
    immutable n = succConns + failConns;
    immutable maxTicks = 50;
    auto provider = new class IConnectionProvider {
        override shared(IConnection) allocate()
        {
            if(succs < succConns)
            {
                succs++;
                return new shared ConnectionCheckConn(uniform(0, maxTicks), maxTicks);
            } else if(fails < failConns)
            {
                fails++;
                return new shared ConnectionCheckConn(maxTicks, uniform(0, maxTicks));
            }
            assert(0);
        }
        
        private uint succs, fails;
    };
   
    auto pool = new AssyncPool(logger, cast(IConnectionProvider)provider, dur!"seconds"(100), dur!"seconds"(100));
    scope(exit) pool.finalize((){});
    pool.addServer("noserver", n);
    
    auto active = pool.activeConnections;
    auto inactive = pool.inactiveConnections;
    auto total = pool.totalConnections;
    
    assert(active + inactive == total, text("Total connections count != active + inactive. ", total, "!=", active,"+",inactive));
    assert(total == n, text("Some connections are lost! ", total, "!=", n));
    
    Thread.sleep(dur!"seconds"(1));
    
    active = pool.activeConnections;
    inactive = pool.inactiveConnections;
    total = pool.totalConnections;
    
    assert(active + inactive == total, text("Total connections count != active + inactive. ", total, "!=", active,"+",inactive));
    assert(total == n, text("Some connections are lost! ", total, "!=", n));
    assert(active == succConns, text("Active connections != succeed connections. ", active,"!=", succConns));
    assert(inactive == failConns, text("Inactive connections != failed connections. ", inactive,"!=", failConns));
}
/**
*   Testing connection process. Some connections can fail and then they should be reconnected again.
*/
unittest
{
    write("Testing async pool. Connection fail after connected... ");
    scope(success) writeln("Finished!");
    scope(failure) writeln("Failed!");
    
    auto logger = new shared CLogger("asyncPool.unittest2");
    scope(exit) logger.finalize();
    logger.minOutputLevel = LoggingLevel.Muted;
    
    synchronized class ConnectionCheckConn : TestConnection
    {
        this(uint ticks, uint failAfter)
        {
            this.ticks = ticks;
            this.failAfter = failAfter;
        }
        
        override void connect(string connString)
        {
            currTicks = 0;
            super.connect(connString);
        }
        
        override ConnectionStatus pollConnectionStatus()
        {
            if(currConnStatus == ConnectionStatus.Pending)
            {
                if(currTicks > ticks) 
                {
                    currConnStatus = ConnectionStatus.Finished;
                } 
            } else if (currConnStatus == ConnectionStatus.Finished)
            {
                if (currTicks > failAfter)
                {
                    currConnStatus = ConnectionStatus.Error;
                    failAfter = uint.max;
                }
            }
            currTicks++;
            return super.pollConnectionStatus();
        }
        
        private uint currTicks;
        private uint ticks, failAfter;
    }
    immutable succConns = 18;
    immutable failConns = 12;
    immutable n = succConns + failConns;
    immutable maxTicks = 100;
    immutable maxFailTicks = 50;
    auto provider = new class IConnectionProvider {
        override shared(IConnection) allocate()
        {
            if(succs < succConns)
            {
                succs++;
                return new shared ConnectionCheckConn(uniform(0, maxTicks), uint.max);
            } else if(fails < failConns)
            {
                fails++;
                return new shared ConnectionCheckConn(uniform(0, maxTicks), uniform(0, maxFailTicks));
            }
            assert(0);
        }
        
        private uint succs, fails;
    };
   
    auto pool = new AssyncPool(logger, cast(IConnectionProvider)provider, dur!"msecs"(100), dur!"msecs"(100));
    scope(exit) pool.finalize((){});
    pool.addServer("noserver", n);
    
    auto active = pool.activeConnections;
    auto inactive = pool.inactiveConnections;
    auto total = pool.totalConnections;
    
    assert(active + inactive == total, text("Total connections count != active + inactive. ", total, "!=", active,"+",inactive));
    assert(total == n, text("Some connections are lost! ", total, "!=", n));

    Thread.sleep(dur!"seconds"(1));

    active = pool.activeConnections;
    inactive = pool.inactiveConnections;
    total = pool.totalConnections;

    assert(active + inactive == total, text("Total connections count != active + inactive. ", total, "!=", active,"+",inactive));
    assert(total == n, text("Some connections are lost! ", total, "!=", n));
    assert(active == n);
}