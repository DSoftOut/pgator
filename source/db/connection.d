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
    @safe pure nothrow this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super("Failed to connect to SQL server, reason: " ~ msg, file, line); 
    }
}

/**
*    Handles a single connection to a SQL server.
*/
interface IConnection
{
    /**
    *    Tries to establish connection with a SQL server described
    *    in $(B connString). 
    *
    *    Throws: ConnectException
    */
    void connect(string connString);
    
    /**
    *    Closes connection to the SQL server after current query completion or
    *    instantly if there is no query processing.    
    *    
    *    Calls $(B callback) when closed.
    */
    void disconnect(void delegate() callback) nothrow;
    
}

