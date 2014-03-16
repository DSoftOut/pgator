// Written in D programming language
/**
*   Default implementation of IConnectionPool. It is consists of four worker thread that holding
*   corresponding connection lists: closed connections, connecting connections, free connections and
*   quering connections.
*
*   Closed connections thread accepts connection to a SQL server and waits specified moment to
*   start establishing process. All failed connections are passed into the worker to try again 
*   later.
*
*   Connecting connections thread handles connection establishing procedure. Connection establishing
*   process is done in asynchronous way (non-blocking polling). All new connections are passed to
*   the worker. If connection is failed, it is passed to closed connections thread, else if it successes,
*   it is passed to free connections thread.
*
*   Free connections thread watch after idle connections. If one want to make a query, pool asks the
*   free connections worker for one. If there is no free connection for specified amount of time,
*   timeout exception is thrown, else returned connection is binded with transaction information and
*   is sent to quering connections worker. Also free connections worker watches after health of each
*   connection, if a free connection dies, it is sent to closed connections process to try to open later.
*   
*   And finally the most interesting one is quering connections worker. The worker accepts all requested
*   transaction to be proceeded on a remote SQL server (several connection could be linked to different servers).
*   Worker starts the transaction, setups all needed local variables and proceeds all requested commands,
*   collects results and transfer them to pool inner queue of finished transactions. Transaction is ended with 
*   "COMMIT;" before sending connection to free connections worker.
*
*   Copyright: © 2014 DSoftOut
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module db.asyncPool;

import log;
import db.pool;
import db.connection;
import db.pq.api;
import derelict.pq.pq;
import std.algorithm;
import std.conv;
import std.container;
import std.concurrency;
import std.datetime;
import std.exception;
import std.range;
import std.typecons;
import core.time;
import core.thread;
import vibe.core.core : yield;
import vibe.data.bson;  
  
/**
*    Describes asynchronous connection pool.
*/
class AsyncPool : IConnectionPool
{
    this(shared ILogger logger, shared IConnectionProvider provider, Duration pReconnectTime, Duration pFreeConnTimeout) shared
    {
        this.logger = logger;
        this.provider = provider;

        mReconnectTime   = pReconnectTime;
        mFreeConnTimeout = pFreeConnTimeout;      
        
        ids = shared ThreadIds(  spawn(&closedChecker, logger, reconnectTime)
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
    void addServer(string connString, size_t connNum) shared
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
                logger.logDebug("Will retry to connect to ", e.server, " over "
                       , reconnectTime.total!"seconds", ".", reconnectTime.fracSec.msecs, " seconds.");
               
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
    
    protected static class Transaction : ITransaction
    {
        this(string[] commands, string[] params, string[string] vars) immutable
        {
            this.commands = commands.idup;
            this.params = params.idup;
            string[string] temp = vars.dup;
            this.vars = assumeUnique(temp);
        }
        
        override bool opEquals(Object o) nothrow 
        {
            auto b = cast(Transaction)o;
            if(b is null) return false;
            
            return commands == b.commands && params == b.params && vars == b.vars;
        }
        
        override hash_t toHash() nothrow @trusted
        {
            auto stringHash = &(typeid(string).getHash);
            
            hash_t toHashArr(immutable string[] arr) nothrow
            {
                hash_t h;
                foreach(elem; arr) h += stringHash(&elem);
                return h;
            }
            
            hash_t toHashAss(immutable string[string] arr) nothrow
            {
                hash_t h;
                scope(failure) return 0;
                foreach(key, val; arr) h += stringHash(&key) + stringHash(&val);
                return h;
            }
            
            return toHashArr(commands) + toHashArr(params) + toHashAss(vars);
        }
        
        override int opCmp(Object o) nothrow
        {
            scope(failure) return -1;
            
            auto b = cast(Transaction)o;
            if(b is null) return -1;
            
            if(this == b) return 0;
            else
            {
                if(commands == b.commands)
                {
                    if(params == b.params)
                    {
                        return cast(int)(vars.length) - cast(int)(b.vars.length);
                    } else return cast(int)(params.length) - cast(int)(b.params.length);
                } else return cast(int)commands.length - cast(int)b.commands.length;
            }
        } 
        
        immutable string[] commands;
        immutable string[] params;
        immutable string[string] vars;
    }
    
    /**
    *   Performs several SQL $(B commands) on single connection
    *   wrapped in a transaction (BEGIN/COMMIT in PostgreSQL).
    *   Each command should use '$n' notation to refer $(B params)
    *   values. Before any command occurs in transaction the
    *   local SQL variables is set from $(B vars). 
    *
    *   Throws: ConnTimeoutException, QueryProcessingException
    */
    InputRange!(immutable Bson) execTransaction(string[] commands, string[] params, string[string] vars) shared
    {
        auto transaction = postTransaction(commands, params, vars);
        while(!isTransactionReady(transaction)) yield;
        return getTransaction(transaction);
    }
    
    /**
    *   Asynchronous way to execute transaction. User can check
    *   transaction status by calling $(B isTransactionReady) method.
    *   When $(B isTransactionReady) method returns true, the
    *   transaction can be finalized by $(B getTransaction) method.
    * 
    *   Returns: Specific interface to distinct the query
    *            among others.
    *   See_Also: isTransactionReady, getTransaction.
    *   Throws: ConnTimeoutException
    */
    immutable(ITransaction) postTransaction(string[] commands, string[] params, string[string] vars) shared
    {
        auto conn = fetchFreeConnection();
        auto transaction = new immutable Transaction(commands, params, vars);
        (cast()processingTransactions).insert(cast(shared)transaction); 
        
        ids.queringCheckerId.send(thisTid, conn, cast(shared)transaction);
        
        return transaction;
    }
    
    /**
    *   Returns true if transaction processing is finished (doesn't
    *   matter the actual reason, error or transaction object is invalid,
    *   or successful completion).
    *
    *   If the method returns true, then $(B getTransaction) method
    *   can be called in non-blocking manner.
    *
    *   See_Also: postTransaction, getTransaction.
    */
    bool isTransactionReady(immutable ITransaction transaction) shared
    {
        scope(failure) return true;

        if((cast()processingTransactions)[].find(cast(shared)transaction).empty)
            return true; 
            
        fetchResponds();

        if(transaction in awaitingResponds) return true;
        else return false;
    }
    
    /**
    *   Retrieves SQL result from specified transaction.
    *   
    *   If previously called $(B isTransactionReady) returns true,
    *   then the method is not blocking, else it falls back
    *   to $(B execTransaction) behavior.
    *
    *   See_Also: postTransaction, isTransactionReady
    *   Throws: UnknownTransactionException, QueryProcessingException
    */
    InputRange!(immutable Bson) getTransaction(immutable ITransaction transaction) shared
    {
        if((cast()processingTransactions)[].find(cast(shared)transaction).empty)
            throw new UnknownTransactionException();
             
        if(transaction in awaitingResponds) 
        {
            auto tempList = (cast()processingTransactions);
            tempList.removeOne(cast(shared)transaction);
            processingTransactions = cast(shared)tempList;
            
            auto respond = awaitingResponds[transaction];
            awaitingResponds.remove(transaction);
            if(respond.failed)
                throw new QueryProcessingException(respond.exception);
            else
                return respond.result[].inputRangeObject;
        } else
        {
            while(!isTransactionReady(transaction)) yield;
            return getTransaction(transaction);
        }
    }
    
    
    private void fetchResponds() shared
    {
        receiveTimeout(dur!"msecs"(1),
            (Tid tid, shared Transaction transaction, Respond respond)
            {
                assert(cast(immutable)transaction !in awaitingResponds);
                awaitingResponds[cast(immutable)transaction] = respond;
            }
        );
    }
    
    /**
    *    If connection to a SQL server is down,
    *    the pool tries to reestablish it every
    *    time units returned by the method. 
    */
    Duration reconnectTime() @property shared
    {
        return mReconnectTime;
    }
    
    /**
    *    If there is no free connection for 
    *    specified duration while trying to
    *    initialize SQL query, then the pool
    *    throws $(B ConnTimeoutException) exception.
    */
    Duration freeConnTimeout() @property shared
    {
        return mFreeConnTimeout;
    }
    
    /**
    *   Returns current alive connections number.
    *   Warning: The method displays count of active connections at the moment,
    *            returned value can become invalid as soon as it returned due
    *            async nature of the pool.
    */
    size_t activeConnections() @property shared
    {
        size_t freeCount, queringCount;
        ids.freeCheckerId.send(thisTid, "length");
        ids.queringCheckerId.send(thisTid, "length");
        
        foreach(i;0..2) 
            try enforce(receiveTimeout(dur!"seconds"(1),
                (Tid sender, size_t answer) 
                {
                    if(sender == ids.freeCheckerId)
                        freeCount = answer;
                    else if(sender == ids.queringCheckerId)
                        queringCount = answer;
                }
            ), "Async pool internal problem! Workers don't respond!");
            catch (LinkTerminated e)
            {
                logger.logError("Free conn or quering conn worker is dead!"); 
                freeCount = 0;
                queringCount = 0;
            }

        return freeCount + queringCount;
    }
    
    /**
    *   Returns current frozen connections number.
    *   Warning: The method displays count of active connections at the moment,
    *            returned value can become invalid as soon as it returned due
    *            async nature of the pool.
    */
    size_t inactiveConnections() @property shared
    {
        size_t closedCount, connectingCount;
        ids.closedCheckerId.send(thisTid, "length");
        ids.connectingCheckerId.send(thisTid, "length");
        
        foreach(i;0..2)
            try enforce(receiveTimeout(dur!"seconds"(1),
                (Tid sender, size_t answer) 
                {
                    if(sender == ids.closedCheckerId)
                        closedCount = answer;
                    else if(sender == ids.connectingCheckerId)
                        connectingCount = answer;
                }
            ), "Async pool internal problem! Workers don't respond!");
            catch (LinkTerminated e)
            {
                logger.logError("Closed conn or connecting conn worker is dead!");
                closedCount = 0;
                connectingCount = 0;
            }

        return closedCount + connectingCount;
    }
    
    size_t totalConnections() @property shared
    {
        size_t freeCount, queringCount;
        size_t closedCount, connectingCount;
        ids.freeCheckerId.send(thisTid, "length");
        ids.queringCheckerId.send(thisTid, "length");
        ids.closedCheckerId.send(thisTid, "length");
        ids.connectingCheckerId.send(thisTid, "length");
        
        foreach(i;0..4)
            try enforce(receiveTimeout(dur!"seconds"(1),
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
            catch (LinkTerminated e)
            {
                logger.logError("One of workers is dead!");
                freeCount = 0;
                queringCount = 0;
                closedCount = 0;
                connectingCount = 0;
            }
        return freeCount + queringCount + closedCount + connectingCount;
    }
    
    /**
    *    Awaits all queries to finish and then closes each connection.
    *    Calls $(B callback) when connections are closed.
    */
    synchronized void finalize()
    {
        if(finalized) return;
        ids.finalize(logger);
        finalized = true;
    }
    
    /**
    *   Returns first free connection from the pool.
    *   Throws: ConnTimeoutException
    */
    protected shared(IConnection) fetchFreeConnection() shared
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

    /**
    *   Returns date format used in ONE OF sql servers.
    *   Warning: This method can be trust only the pool conns are connected
    *            to the same sql server.
    *   TODO: Make a way to get such configs for particular connection.
    */
    DateFormat dateFormat() @property shared
    {
        return fetchFreeConnection.dateFormat;
    }
    
    /**
    *   Returns timestamp format used in ONE OF sql servers.
    *   Warning: This method can be trust only the pool conns are connected
    *            to the same sql server.
    *   TODO: Make a way to get such configs for particular connection.
    */
    TimestampFormat timestampFormat() @property shared
    {
        return fetchFreeConnection.timestampFormat;
    }
    
    /**
    *   Returns server time zone used in ONE OF sql servers.
    *   Warning: This method can be trusted only the pool conns are connected
    *            to the same sql server.
    *   TODO: Make a way to get such configs for particular connection.
    */
    immutable(TimeZone) timeZone() @property shared
    {
        return fetchFreeConnection.timeZone;
    }
    
    private
    {
       shared ILogger logger;
       shared DList!(shared ITransaction) processingTransactions;
       Respond[immutable ITransaction] awaitingResponds;
       IConnectionProvider provider;
       Duration mReconnectTime;
       Duration mFreeConnTimeout;
       
       /// Worker returns this as query result
       struct Respond
       {
           this(QueryException e)
           {
               failed = true;
               exception = e.msg;
           }
           
           bool collect(DList!(shared IPGresult) results, shared IConnection conn)
           {
               foreach(res; results)
               {
                  if(res.resultStatus != ExecStatusType.PGRES_TUPLES_OK &&
                     res.resultStatus != ExecStatusType.PGRES_COMMAND_OK)
                  {
                      failed = true;
                      exception = res.resultErrorMessage;
                      return false;
                  }
                  result ~= cast(immutable)res.asColumnBson(conn);
                  res.clear();
               }
               return true;
           }
           
           bool failed = false;
           string exception;
           immutable(Bson)[] result;
       }
       
       shared struct ThreadIds
       {
           immutable Tid mClosedCheckerId;
           immutable Tid mFreeCheckerId;
           immutable Tid mConnectingCheckerId;
           immutable Tid mQueringCheckerId;
           
           Tid closedCheckerId()
           {
               return cast()mClosedCheckerId;
           }
           
           Tid freeCheckerId()
           {
               return cast()mFreeCheckerId;
           }
           
           Tid connectingCheckerId()
           {
               return cast()mConnectingCheckerId;
           }
           
           Tid queringCheckerId()
           {
               return cast()mQueringCheckerId;
           }
           
           this(Tid closedCheckerId, Tid freeCheckerId, Tid connectingCheckerId, Tid queringCheckerId)
           {
               this.mClosedCheckerId     = cast(immutable)closedCheckerId;
               this.mFreeCheckerId       = cast(immutable)freeCheckerId;
               this.mConnectingCheckerId = cast(immutable)connectingCheckerId;
               this.mQueringCheckerId    = cast(immutable)queringCheckerId;
           }
           
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
           
           static shared(ThreadIds) receive()
           {
               auto closedTid = receiveOnly!Tid();
               auto freeTid = receiveOnly!Tid();
               auto connectingTid = receiveOnly!Tid();
               auto queringTid = receiveOnly!Tid();
               return shared ThreadIds(closedTid, freeTid, connectingTid, queringTid);
           }
           
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
       shared ThreadIds ids;
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
       
       static void freeChecker(shared ILogger logger, Duration reconnectTime)
       {
           try 
           {
               setMaxMailboxSize(thisTid, 0, OnCrowding.block);
               Thread.getThis.isDaemon = true;
               
               DList!Tid connRequests;
               ConnectionList list;
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
                               logger.logInfo(text("Will retry to connect to ", e.server, " over "
                                       , reconnectTime.total!"seconds", ".", reconnectTime.fracSec.msecs, " seconds."));
                               list.removeOne(conn);
                           
                               TickDuration whenRetry = TickDuration.currSystemTick + cast(TickDuration)reconnectTime;
                               ids.closedCheckerId.send("add", conn, whenRetry);
                           }
                       }
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
       
       static void connectingChecker(shared ILogger logger, Duration reconnectTime)
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
                                   logger.logDebug(text("Will retry to connect to ", e.server, " over "
                                       , reconnectTime.total!"seconds", ".", reconnectTime.fracSec.msecs, " seconds."));
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
       
       static void queringChecker(shared ILogger logger)
       {
           struct Element
           {
               Tid sender;
               shared IConnection conn;
               
               immutable Transaction transaction;
               private size_t transactPos = 0;
               private immutable string[] varsQueries;
               private size_t localVars = 0;
               private bool transStarted = false;
               private bool transEnded = false;
               private bool commandPosting = false;
               
               enum Stage
               {
                   MoreQueries,
                   Proccessing,
                   Finished
               }
               Stage stage = Stage.MoreQueries;
               private Respond respond;
               
               this(Tid sender, shared IConnection conn, immutable Transaction transaction)
               {
                   this.sender = sender;
                   this.conn = conn;
                   this.transaction = transaction;
                   
                   foreach(key, value; transaction.vars)
                   {
                       varsQueries ~= `SET LOCAL "`~key~`" = '`~value~`';`; 
                   } 
               }
               
               void postQuery()
               {
                   assert(stage == Stage.MoreQueries); 
                   
                   if(!transStarted)
                   {
                       transStarted = true; 
                       try conn.postQuery("BEGIN;", []);
                       catch(QueryException e)
                       {
                           respond = Respond(e);                
                           stage = Stage.Finished;
                           return;
                       }
                       catch (Exception e)
                       {
                           respond = Respond(new QueryException("Internal error: "~e.msg));
                           stage = Stage.Finished;
                           return;
                       }
                       stage = Stage.Proccessing;                
                       return;
                   }
                   
                   if(localVars < varsQueries.length)
                   {
                       try 
                       {    
                           conn.postQuery(varsQueries[localVars], []); 
                           localVars++; 
                       }
                       catch (QueryException e)
                       {
                          respond = Respond(e);                
                          stage = Stage.Finished;
                          return;
                       }
                       catch (Exception e)
                       {
                           respond = Respond(new QueryException("Internal error: "~e.msg));
                           stage = Stage.Finished;
                           return;
                       }
                       stage = Stage.Proccessing;                
                       return;
                   }
                   
                   if(transactPos < transaction.commands.length)
                   {
                       commandPosting = true;
                       try 
                       {
                           conn.postQuery(transaction.commands[transactPos], transaction.params.dup);  
                           transactPos++; 
                       }
                       catch (QueryException e)
                       {
                          respond = Respond(e);                
                          stage = Stage.Finished;
                          return;
                       }
                       catch (Exception e)
                       {
                           respond = Respond(new QueryException("Internal error: "~e.msg));
                           stage = Stage.Finished;
                           return;
                       }
                       stage = Stage.Proccessing;                
                       return;
                   }
                   
                   if(!transEnded)
                   {
                       commandPosting = false;
                       transEnded = true; 
                       try conn.postQuery("COMMIT;", []);
                       catch(QueryException e)
                       {
                           respond = Respond(e);                
                           stage = Stage.Finished;
                           return;
                       }
                       catch (Exception e)
                       {
                           respond = Respond(new QueryException("Internal error: "~e.msg));
                           stage = Stage.Finished;
                           return;
                       }
                       stage = Stage.Proccessing;                
                       return;
                   }
                   
                   assert(false);
               }
               
               private bool hasMoreQueries()
               {
                   return !transStarted || !transEnded || localVars < varsQueries.length || transactPos < transaction.commands.length;
               }
               
               private bool needCollectResult()
               {
                   return commandPosting;
               }
               
               void stepQuery()
               {
                   assert(stage == Stage.Proccessing);                
                   
                   final switch(conn.pollQueringStatus())
                   {
                       case QueringStatus.Pending:
                       { 
                           return;                
                       }
                       case QueringStatus.Error:
                       {
                           try conn.pollQueryException();
                           catch(QueryException e)
                           {
                               respond = Respond(e);
                               stage = Stage.Finished;
                               return;
                           } 
                           catch (Exception e)
                           {
                               respond = Respond(new QueryException("Internal error: "~e.msg));
                               stage = Stage.Finished;
                               return;
                           }
                           break;
                       }
                       case QueringStatus.Finished:
                       {
                           try 
                           {
                               auto res = conn.getQueryResult;
                               if(needCollectResult) 
                               {
                                   if(!respond.collect(res, conn))
                                   {
                                       stage = Stage.Finished;
                                       return;
                                   }
                               }
                                             
                               if(!hasMoreQueries)
                               {
                                   stage = Stage.Finished; 
                                   return;
                               }
                               stage = Stage.MoreQueries;
                           }
                           catch(QueryException e)
                           {
                               respond = Respond(e);
                               stage = Stage.Finished;                            
                               return;
                           } 
                           catch (Exception e)
                           {
                               respond = Respond(new QueryException("Internal error: "~e.msg));
                               stage = Stage.Finished;
                               return;
                           }
                           break;
                       }
                   }
               }
               
               void sendRespond()
               {
                   sender.send(thisTid, cast(shared)transaction, respond);            
               }
           }
           
           
           try
           {
               setMaxMailboxSize(thisTid, 0, OnCrowding.block);
               Thread.getThis.isDaemon = true;
               
               DList!Element list;
               auto ids = ThreadIds.receive();
              
               bool exit = false;
               Tid exitTid;
               size_t last = list[].walkLength;
               while(!exit || last > 0)
               {
                   while(receiveTimeout(dur!"msecs"(1)
                       , (Tid sender, bool v) 
                           {
                               exit = v; 
                               exitTid = sender;
                           }
                       , (Tid sender, shared IConnection conn, shared Transaction transaction) 
                           {
                               list.insert(Element(sender, conn, cast(immutable)transaction));
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
                   
                   DList!Element nextList;
                   foreach(ref elem; list[])
                   {
                       final switch(elem.stage)
                       {
                           case Element.Stage.MoreQueries:
                           {
                               elem.postQuery();
                               nextList.insert(elem);
                               break;
                           }
                           case Element.Stage.Proccessing:
                           {
                               elem.stepQuery();
                               nextList.insert(elem);
                               break;
                           }
                           case Element.Stage.Finished:
                           {
                               elem.sendRespond();
                               
                               if(exit) elem.conn.disconnect();
                               else ids.freeCheckerId.send("add", elem.conn);
                           }
                       }
                   }
                   list = nextList;
                   last = list.length;
               }
    
               exitTid.send(true);
               logger.logDebug("Quering thread exited!");
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
            return currQueringStatus;
        } 

        void pollQueryException()
        {
            throw new QueryException("Test query is failed!");
        }
        
        DList!(shared IPGresult) getQueryResult()
        {
            assert(false, "Not used!");
        }
        
        void postQuery(string com, string[] params)
        {
            assert(false, "Not used!");
        }
        
        void disconnect() nothrow
        {
            currConnStatus = ConnectionStatus.Error;
        }
        
        string server() const nothrow
        {
            return "";
        }

        DateFormat dateFormat() @property shared
        {
            return DateFormat("ISO", "DMY");
        }
        
        TimestampFormat timestampFormat() @property
        {
            return TimestampFormat.Int64; 
        }
        
        immutable(TimeZone) timeZone() @property
        {
            return UTC(); 
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
    
    auto logger = new shared CLogger("logs/asyncPool.unittest2.log");
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
    
    synchronized class LocalProvider : IConnectionProvider {
        override synchronized shared(IConnection) allocate()
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
    }
    
    shared IConnectionProvider provider = new shared LocalProvider();
   
    auto pool = new shared AsyncPool(logger, provider, dur!"msecs"(500), dur!"msecs"(500));
    scope(exit) pool.finalize();
    pool.addServer("noserver", n);
    
    auto active = pool.activeConnections;
    auto inactive = pool.inactiveConnections;
    auto total = pool.totalConnections;

    Thread.sleep(dur!"seconds"(3));

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
    
    auto logger = new shared CLogger("logs/asyncPool.unittest1.log");
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
    
    synchronized class LocalProvider : IConnectionProvider {
        override synchronized shared(IConnection) allocate()
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
    }
    
    shared IConnectionProvider provider = new shared LocalProvider();
    
    auto pool = new shared AsyncPool(logger, provider, dur!"seconds"(100), dur!"seconds"(100));
    scope(exit) pool.finalize();
    pool.addServer("noserver", n);
    
    auto active = pool.activeConnections;
    auto inactive = pool.inactiveConnections;
    auto total = pool.totalConnections;
    
    Thread.sleep(dur!"seconds"(3));
    
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
    
    auto logger = new shared CLogger("logs/asyncPool.unittest2.log");
    scope(exit) logger.finalize();
    logger.minOutputLevel = LoggingLevel.Fatal;
    
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
    synchronized class LocalProvider : IConnectionProvider {
        override synchronized shared(IConnection) allocate()
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
    }
    
    shared IConnectionProvider provider = new shared LocalProvider();
    auto pool = new shared AsyncPool(logger, provider, dur!"msecs"(100), dur!"msecs"(100));
    scope(exit) pool.finalize();
    pool.addServer("noserver", n);
    
    auto active = pool.activeConnections;
    auto inactive = pool.inactiveConnections;
    auto total = pool.totalConnections;

    Thread.sleep(dur!"seconds"(3));

    active = pool.activeConnections;
    inactive = pool.inactiveConnections;
    total = pool.totalConnections;

    assert(active + inactive == total, text("Total connections count != active + inactive. ", total, "!=", active,"+",inactive));
    assert(total == n, text("Some connections are lost! ", total, "!=", n));
    assert(active == n);
}