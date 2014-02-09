// Written in D programming language
/**
*    
*    Authors: NCrashed <ncrashed@gmail.com>
*/
module db.connection;

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
    /**
    *    Tries to establish connection with a SQL server described
    *    in $(B connString). 
    */
    void connect(string connString);
    
    /**
    *   Returns current status of connection.
    */
    ConnectionStatus pollConnectionStatus();
    
    /**
    *   If connection process is ended with error state, then
    *   throws ConnectException, else do nothing.
    *
    *   Throws: ConnectException
    */    
    void pollConnectionException();
    
    /**
    *   Returns quering status of connection.
    */
    QueringStatus pollQueringStatus();
    
    /**
    *   If quering process is ended with error state, then
    *   throws QueryException, else do nothing.
    *
    *   Throws: QueryException
    */
    void pollQueryException();
    
    /**
    *    Closes connection to the SQL server instantly.    
    *    
    *    Also should interrupt connections in progress.
    *
    *    Calls $(B callback) when closed.
    */
    void disconnect() nothrow;
    
}