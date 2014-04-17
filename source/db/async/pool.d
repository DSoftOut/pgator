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
module db.async.pool;

import dlogg.log;
public import db.pool;
import db.connection;
import db.pq.api;
import std.algorithm;
import std.container;
import std.concurrency;
import std.datetime;
import std.exception;
import std.range;
import core.thread;
import vibe.core.core : yield;
import vibe.data.bson;  
import util;

import db.async.respond;
import db.async.transaction;
import db.async.workers.handler;
import db.async.workers.closed;
import db.async.workers.free;
import db.async.workers.connecting;
import db.async.workers.query; 
 
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
        , string[string] vars = null) shared
    {
        ///TODO: move to contract when issue with contracts is fixed
        assert(!finalized, "Pool was finalized!");
        
        /// Workaround for gdc
        if(vars is null)
        {
            string[string] empty;
            vars = empty;
        }
        
        auto transaction = postTransaction(commands, params, argnums, vars);
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
        , string[string] vars = null) shared
    {
        ///TODO: move to contract when issue with contracts is fixed
        assert(!finalized, "Pool was finalized!");
        
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
        auto transaction = new immutable Transaction(commands, params, argnums, vars);
        processingTransactions.insert(cast(shared)transaction); 
        
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
   }
}
version(unittest)
{
    import std.stdio;
    import std.random;
    import core.thread;
    import dlogg.strict;
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
        
        bool testAlive() shared nothrow
        {
            return true;
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
    
    auto logger = new shared StrictLogger("logs/asyncPool.unittest2.log");
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
   
    auto pool = new shared AsyncPool(logger, provider, dur!"msecs"(500), dur!"msecs"(500), dur!"seconds"(3));
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
    
    auto logger = new shared StrictLogger("logs/asyncPool.unittest1.log");
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
    
    auto pool = new shared AsyncPool(logger, provider, dur!"seconds"(100), dur!"seconds"(100), dur!"seconds"(3));
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
    
    auto logger = new shared StrictLogger("logs/asyncPool.unittest2.log");
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
    auto pool = new shared AsyncPool(logger, provider, dur!"msecs"(100), dur!"msecs"(100), dur!"seconds"(3));
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
