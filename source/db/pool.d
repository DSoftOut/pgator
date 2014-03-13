// Written in D programming language
/**
*    Module describes connection pool to data bases. Pool handles
*    several connections to one or more sql servers. If connection
*    is lost, pool tries to reconnect over $(B reconnectTime) duration.
*    
*    Copyright: © 2014 DSoftOut
*    License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*    Authors: NCrashed <ncrashed@gmail.com>
*/
module db.pool;

import db.connection;
import db.pq.api;
import std.datetime;
import std.range;
import core.time;
import vibe.data.bson;

/**
*    The exception is thrown when there is no any free connection
*    for $(B freeConnTimeout) duration while trying to lock one.
*/
class ConnTimeoutException : Exception
{
    @safe pure nothrow this(string file = __FILE__, size_t line = __LINE__)
    {
        super("There is no any free connection to SQL servers!", file, line); 
    }
}

/**
*   The exception is thrown when invalid transaction interface is passed to
*   $(B isTransactionReady) and $(B getTransaction) methods.
*/
class UnknownTransactionException : Exception
{
    @safe pure nothrow this(string file = __FILE__, size_t line = __LINE__)
    {
        super("There is no such transaction that is processing now!", file, line); 
    }
}

/**
*   The exception is thrown when something bad has happen while 
*   query passing to server or loading from server. This exception
*   has no bearing on the SQL errors.
*/
class QueryProcessingException : Exception
{
    @safe pure nothrow this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line); 
    }
}

/**
*    Pool handles several connections to one or more SQL servers. If 
*    connection is lost, pool tries to reconnect over $(B reconnectTime) 
*    duration.
*
*    
*/
interface IConnectionPool
{
    /**
    *    Adds connection string to a SQL server with
    *    maximum connections count.
    *
    *    The pool will try to reconnect to the sql 
    *    server every $(B reconnectTime) is connection
    *    is dropped (or is down initially).
    */
    void addServer(string connString, size_t connNum) shared;
    
    /**
    *   Performs several SQL $(B commands) on single connection
    *   wrapped in a transaction (BEGIN/COMMIT in PostgreSQL).
    *   Each command should use '$n' notation to refer $(B params)
    *   values. Before any command occurs in transaction the
    *   local SQL variables is set from $(B vars). 
    *
    *   Throws: ConnTimeoutException, QueryProcessingException
    */
    InputRange!(immutable Bson) execTransaction(string[] commands, string[] params = [], string[string] vars = AssociativeArray!(string, string)()) shared;
    
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
    immutable(ITransaction) postTransaction(string[] commands, string[] params = [], string[string] vars = AssociativeArray!(string, string)()) shared;
    
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
    bool isTransactionReady(immutable ITransaction transaction) shared;
    
    /**
    *   Retrieves SQL result from specified transaction.
    *   
    *   If previously called $(B isTransactionReady) returns true,
    *   then the method is not blocking, else it falls back
    *   to $(B execTransaction) behavior.
    *
    *   See_Also: postTransaction, isTransactionReady
    *   Throws: UnknownQueryException, QueryProcessingException
    */
    InputRange!(immutable Bson) getTransaction(immutable ITransaction transaction) shared;
    
    /**
    *    If connection to a SQL server is down,
    *    the pool tries to reestablish it every
    *    time units returned by the method. 
    */
    Duration reconnectTime() @property shared;
    
    /**
    *    If there is no free connection for 
    *    specified duration while trying to
    *    initialize SQL query, then the pool
    *    throws $(B ConnTimeoutException) exception.
    */
    Duration freeConnTimeout() @property shared;
    
    /**
    *    Returns current alive connections number.
    */
    size_t activeConnections() @property shared;

    /**
    *    Returns current frozen connections number.
    */
    size_t inactiveConnections() @property shared;
        
    /**
    *    Awaits all queries to finish and then closes each connection.
    */
    synchronized void finalize();
    
    /**
    *   Returns date format used in ONE OF sql servers.
    *   Warning: This method can be trusted only the pool conns are connected
    *            to the same sql server.
    *   TODO: Make a way to get such configs for particular connection.
    */
    DateFormat dateFormat() @property shared;
    
    /**
    *   Returns timestamp format used in ONE OF sql servers.
    *   Warning: This method can be trusted only the pool conns are connected
    *            to the same sql server.
    *   TODO: Make a way to get such configs for particular connection.
    */
    TimestampFormat timestampFormat() @property shared;
    
    /**
    *   Returns server time zone used in ONE OF sql servers.
    *   Warning: This method can be trusted only the pool conns are connected
    *            to the same sql server.
    *   TODO: Make a way to get such configs for particular connection.
    */
    immutable(TimeZone) timeZone() @property shared;
    
    /**
    *   Returns first free connection from the pool.
    *   Throws: ConnTimeoutException
    */
    protected shared(IConnection) fetchFreeConnection() shared;
    
    protected interface ITransaction {}
}
