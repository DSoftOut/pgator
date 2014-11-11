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
module pgator.db.async.pool;

import dlogg.log;
public import pgator.db.pool;
import pgator.db.connection;
import pgator.db.pq.api;
import pgator.util.list;
import std.algorithm;
import std.container;
import std.concurrency;
import std.datetime;
import std.exception;
import std.range;
import core.thread;
import core.atomic;
import vibe.core.core : yield;
import vibe.data.bson;  

import pgator.db.async.respond;
import pgator.db.async.transaction;
import pgator.db.async.workers.handler;
import pgator.db.async.workers.closed;
import pgator.db.async.workers.free;
import pgator.db.async.workers.connecting;
import pgator.db.async.workers.query; 
 
/**
*    Describes asynchronous connection pool.
*/
class AsyncPool : IConnectionPool
{
    this(shared ILogger logger, shared IConnectionProvider provider, Duration pReconnectTime, Duration pFreeConnTimeout, Duration pAliveCheckTime) shared
    {
        this.logger = logger;
        this.provider = provider;

        mReconnectTime   = pReconnectTime;
        mFreeConnTimeout = pFreeConnTimeout;      
        mAliveCheckTime  = pAliveCheckTime;
        
        ids = shared ThreadIds(  spawn(&closedChecker, logger, reconnectTime)
                        , spawn(&freeChecker, logger, reconnectTime, aliveCheckTime)
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
        ///TODO: move to contract when issue with contracts is fixed
        assert(!finalized, "Pool was finalized!");
        
        TimedConnList failedList;
        DList!(shared IConnection) connsList;
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
                static if (__VERSION__ < 2066) {
	                logger.logDebug("Will retry to connect to ", e.server, " over "
	                       , reconnectTime.total!"seconds", ".", reconnectTime.fracSec.msecs, " seconds.");
                } else {
	                logger.logDebug("Will retry to connect to ", e.server, " over "
	                       , reconnectTime.total!"seconds", ".", reconnectTime.split!("seconds", "msecs").msecs, " seconds.");
                }
                
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
    
    /**
    *   Performs several SQL $(B commands) on single connection
    *   wrapped in a transaction (BEGIN/COMMIT in PostgreSQL).
    *   Each command should use '$n' notation to refer $(B params)
    *   values. Before any command occurs in transaction the
    *   local SQL variables is set from $(B vars). 
    *
    *   Throws: ConnTimeoutException, QueryProcessingException
    */
    InputRange!(immutable Bson) execTransaction(string[] commands
        , string[] params = [], uint[] argnums = []
        , string[string] vars = null, bool[] oneRowConstraint = []) shared
    {
        ///TODO: move to contract when issue with contracts is fixed
        assert(!finalized, "Pool was finalized!");
        
        /// Workaround for gdc
        if(vars is null)
        {
            string[string] empty;
            vars = empty;
        }
        
        auto transaction = postTransaction(commands, params, argnums, vars, oneRowConstraint);
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
    immutable(ITransaction) postTransaction(string[] commands
        , string[] params = [], uint[] argnums = []
        , string[string] vars = null, bool[] oneRowConstraint = []) shared
    {
        ///TODO: move to contract when issue with contracts are fixed
        assert(!finalized, "Pool was finalized!");
        assert(oneRowConstraint.length == 0 || oneRowConstraint.length == commands.length
            , "oneRowConstraint have to have length equal to commands length!");
        
        if(oneRowConstraint.length == 0)
        {
            oneRowConstraint = new bool[commands.length];
            oneRowConstraint[] = false;
        }
        
        /// Workaround for gdc
        if(vars is null)
        {
            string[string] empty;
            vars = empty;
        }
        
        if(params.length == 0 && argnums.length == 0)
        {
            argnums = 0u.repeat.take(commands.length).array;
        }
        
        auto conn = fetchFreeConnection();
        auto transaction = new immutable Transaction(commands, params, argnums, vars, oneRowConstraint);
        processingTransactions.insert(cast(shared)transaction); 
        
        ids.queringCheckerId.send(thisTid, conn, cast(shared)transaction);
        
        if(loggingAllTransactions)
        {
            logger.logInfo("Transaction is posted:");
            logger.logInfo(transaction.text);
        }
        
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
        ///TODO: move to contract when issue with contracts is fixed
        assert(!finalized, "Pool was finalized!");
        
        scope(failure) return true;

        if(processingTransactions[].find(cast(shared)transaction).empty)
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
        ///TODO: move to contract when issue with contracts is fixed
        assert(!finalized, "Pool was finalized!");
        
        if(processingTransactions[].find(cast(shared)transaction).empty)
            throw new UnknownTransactionException();
                
        if(transaction in awaitingResponds) 
        {
            processingTransactions.removeOne(cast(shared)transaction);
            
            auto tr = cast(Transaction)transaction;
            assert(tr);
            
            auto respond = awaitingResponds[transaction];
            awaitingResponds.remove(transaction);
            
            void logMessages(void delegate(string msg) sink)
            {
                if(respond.msgs.length != 0)
                {
                    sink("Following messages were raised from db:");
                    foreach(msg; respond.msgs) 
                    {
                        if(msg.length > 0 && msg[$-1] == '\n') sink(msg[0 .. $-1]);
                        else sink(msg);
                    }
                }
            }
            
            if(respond.failed)
            {
                if(respond.onRowConstaintFailed)
                {
                    logger.logError("Transaction failure: ");
                    logger.logError(text(tr));
                    auto errMsg = text("Transaction ", respond.constraintFailQueryId, " fired single row constraint!" );
                    logger.logError(errMsg);
                    throw new OneRowConstraintException(errMsg);
                } 
                else
                {
                    logger.logError("Transaction failure:");
                    logger.logError(text(tr));
                    logMessages((s) => logger.logError(s));
                    
                    throw new QueryProcessingException(respond.exception);
                }
            }
            else
            {
                if(respond.msgs.length != 0)
                {
                    logMessages((s) => logger.logInfo(s));
                    logger.logInfo("For transaction:");
                    logger.logInfo(text(tr));
                }
                
                return respond.result[].inputRangeObject;
            }
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
        ///TODO: move to contract when issue with contracts is fixed
        assert(!finalized, "Pool was finalized!");
        
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
        ///TODO: move to contract when issue with contracts is fixed
        assert(!finalized, "Pool was finalized!");
        
        return mFreeConnTimeout;
    }
    
    /**
    *   Free connections are checked over the time by
    *   sending senseless queries. Don't make this time
    *   too small - huge overhead for network. Don't make
    *   this time too big - you wouldn't able to detect
    *   failed connections due server restarting or e.t.c.
    */
    Duration aliveCheckTime() @property shared
    {
        ///TODO: move to contract when issue with contracts is fixed
        assert(!finalized, "Pool was finalized!");
        
        return mAliveCheckTime;
    }
    
    /**
    *   Returns current alive connections number.
    *   Warning: The method displays count of active connections at the moment,
    *            returned value can become invalid as soon as it returned due
    *            async nature of the pool.
    */
    size_t activeConnections() @property shared
    {
        ///TODO: move to contract when issue with contracts is fixed
        assert(!finalized, "Pool was finalized!");
        
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
        ///TODO: move to contract when issue with contracts is fixed
        assert(!finalized, "Pool was finalized!");
        
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
        ///TODO: move to contract when issue with contracts is fixed
        assert(!finalized, "Pool was finalized!");
        
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
        ///TODO: move to contract when issue with contracts is fixed
        assert(!finalized, "Pool was finalized!");
                
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
        ///TODO: move to contract when issue with contracts is fixed
        assert(!finalized, "Pool was finalized!");
        
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
        ///TODO: move to contract when issue with contracts is fixed
        assert(!finalized, "Pool was finalized!");
        
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
        ///TODO: move to contract when issue with contracts is fixed
        assert(!finalized, "Pool was finalized!");
        
        return fetchFreeConnection.timeZone;
    }
    
    /**
    *   Returns $(B true) if the pool logs all transactions.
    */
    bool loggingAllTransactions() shared const
    {
        return mLoggingAll;
    }
    
    /**
    *   Enables/disables logging for all transactions.
    */
    void loggingAllTransactions(bool val) shared
    {
        mLoggingAll.atomicStore(val);
    }
    
    private
    {
       shared ILogger logger;
       __gshared DList!(shared ITransaction) processingTransactions;
       Respond[immutable ITransaction] awaitingResponds;
       IConnectionProvider provider;
       Duration mReconnectTime;
       Duration mFreeConnTimeout;
       Duration mAliveCheckTime;
       
       shared ThreadIds ids;
       bool finalized = false;
       bool mLoggingAll = false;
   }
}