// Written in D programming language
/**
*    
*    Authors: NCrashed <ncrashed@gmail.com>
*/
module db.connection;

import db.pq.api;
import dunit.mockable;
import std.container;

/**
*    The exception is thrown when connection attempt to SQL server is failed due some reason.
*/
class ConnectException : Exception
{
    string server;
    
    @safe pure nothrow this(string server, string msg, string file = __FILE__, size_t line = __LINE__)
    {
        this.server = server;
        super("Failed to connect to SQL server "~server~", reason: " ~ msg, file, line); 
    }
}

/**
*   The exception is thrown when $(B reconnect) method is called, but there wasn't any call of
*   $(B connect) method to grab connection string from.
*/
class ReconnectException : ConnectException
{
    @safe pure nothrow this(string server, string file = __FILE__, size_t line = __LINE__)
    {
        super(server, "Connection reconnect method is called, but there wasn't any call of "
                      "connect method to grab connection string from", file, line);
    }
}

/**
*   The exception is thrown when query is failed due some reason.
*/
class QueryException : Exception
{
    @safe pure nothrow this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super("Query to SQL server is failed, reason: " ~ msg, file, line); 
    }
}

/**
*   Describes result of connection status polling.
*/
enum ConnectionStatus
{
    /// Connection is in progress
    Pending,
    /// Connection is finished with error
    Error,
    /// Connection is finished successfully
    Finished
}

/**
*   Describes result of quering status polling.
*/
enum QueringStatus
{
    /// Quering is in progress
    Pending,
    /// SQL server returned an error
    Error,
    /// SQL server returned normal result
    Finished
}

/**
*    Handles a single connection to a SQL server.
*/
interface IConnection
{
    synchronized:
    
    /**
    *    Tries to establish connection with a SQL server described
    *    in $(B connString). 
    *
    *    Throws: ConnectException
    */
    void connect(string connString);
    
    /**
    *   Tries to establish connection with a SQL server described
    *   in previous call of $(B connect). 
    *
    *   Should throw ReconnectException if method cannot get stored
    *   connection string (the $(B connect) method wasn't called).
    *
    *   Throws: ConnectException, ReconnectException
    */
    void reconnect();
    
    /**
    *   Returns current status of connection.
    */
    ConnectionStatus pollConnectionStatus() nothrow;
    
    /**
    *   If connection process is ended with error state, then
    *   throws ConnectException, else do nothing.
    *
    *   Throws: ConnectException
    */    
    void pollConnectionException();
    
    /**
    *   Initializes querying process in non-blocking manner.
    *   Throws: QueryException
    */
    void postQuery(string com, string[] params);
    
    /**
    *   Returns quering status of connection.
    */
    QueringStatus pollQueringStatus() nothrow;
    
    /**
    *   If quering process is ended with error state, then
    *   throws QueryException, else do nothing.
    *
    *   Throws: QueryException
    */
    void pollQueryException();
    
    /**
    *   Returns query result, if $(B pollQueringStatus) shows that
    *   query is processed without errors, else blocks the caller
    *   until the answer is arrived.
    */
    DList!(shared IPGresult) getQueryResult();
    
    /**
    *    Closes connection to the SQL server instantly.    
    *    
    *    Also should interrupt connections in progress.
    *
    *    Calls $(B callback) when closed.
    */
    void disconnect() nothrow;
    
    /**
    *   Returns SQL server name (domain) the connection is desired to connect to.
    *   If connection isn't ever established (or tried) the method returns empty string.
    */
    string server() nothrow const @property;
    
    mixin Mockable!IConnection;
}

/**
*   Interface that produces connection objects. Used
*   to isolate connection pool from particular connection
*   realization.
*/
interface IConnectionProvider
{
    /**
    *   Allocates new connection shared across threads.
    */
    shared(IConnection) allocate();
    
    mixin Mockable!IConnection;
}