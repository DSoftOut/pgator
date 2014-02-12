// Written in D programming language
/**
*   Module describes a real connection to PostgreSQL server.
*
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module db.pq.connection;

import dunit.mockable;
import derelict.pq.pq;
import db.connection;
import db.pq.api;
import log;
import std.conv;

/**
*   PostgreSQL specific connection type. Although it can use
*   different data base backend, the class is defined to 
*   support only PostgreSQL.
*/
synchronized class PQConnection : IConnection
{
    this(shared ILogger logger, IPostgreSQL api)
    {
        this.logger = logger;
        this.api = api;
    }
    
    /**
    *    Tries to establish connection with a SQL server described
    *    in $(B connString). 
    *
    *    Throws: ConnectException
    */
    void connect(string connString)
    {
        if(conn !is null) conn.finish;
        
        try
        {
            conn = api.startConnect(connString);
            reconnecting = false;
        } catch(PGException e)
        {
            logger.logError(text("Failed to connect to SQL server, reason:", e.msg));
            throw new ConnectException(server, e.msg);
        }
    }
    
    /**
    *   Tries to establish connection with a SQL server described
    *   in previous call of $(B connect). 
    *
    *   Should throw ReconnectException if method cannot get stored
    *   connection string (the $(B connect) method wasn't called).
    *
    *   Throws: ConnectException, ReconnectException
    */
    void reconnect()
    {
        if(conn is null) throw new ReconnectException(server);
        
        try
        {
            conn.resetStart();
            reconnecting = true;
        } catch(PGReconnectException e)
        {
            logger.logError(text("Failed to reconnect to SQL server, reason:", e.msg));
            throw new ConnectException(server, e.msg);
        }
    }
    
    /**
    *   Returns current status of connection.
    */
    ConnectionStatus pollConnectionStatus() nothrow
    in
    {
        assert(conn !is null, "Connection start wasn't established!");
    }
    body
    {
        savedException = null;
        PostgresPollingStatusType val;
        if(reconnecting) val = conn.resetPoll;
        else val = conn.poll;
        
        switch(val)
        {
            case PostgresPollingStatusType.PGRES_POLLING_OK:
            {
                switch(conn.status)
                {
                    case(ConnStatusType.CONNECTION_OK):
                    {
                        return ConnectionStatus.Finished;
                    }
                    case(ConnStatusType.CONNECTION_NEEDED):
                    {
                        savedException = new ConnectException(server, "Connection wasn't tried to be established!");
                        return ConnectionStatus.Error;
                    }
                    case(ConnStatusType.CONNECTION_BAD):
                    {
                        savedException = new ConnectException(server, conn.errorMessage);
                        return ConnectionStatus.Error;
                    }
                    default:
                    {
                        return ConnectionStatus.Pending;
                    }
                }
            }
            case PostgresPollingStatusType.PGRES_POLLING_FAILED:
            {
                savedException = new ConnectException(server, conn.errorMessage);
                return ConnectionStatus.Error;
            }
            default:
            {
                return ConnectionStatus.Pending;
            } 
        }
    }
    
    /**
    *   If connection process is ended with error state, then
    *   throws ConnectException, else do nothing.
    *
    *   Throws: ConnectException
    */    
    void pollConnectionException()
    {
        if(savedException !is null) throw savedException;
    }
    
    /**
    *   Returns quering status of connection.
    */
    QueringStatus pollQueringStatus() nothrow
    {
        assert(false, "Undefined!");
    }
    
    /**
    *   If quering process is ended with error state, then
    *   throws QueryException, else do nothing.
    *
    *   Throws: QueryException
    */
    void pollQueryException()
    {
        assert(false, "Undefined!");
    }
    
    /**
    *    Closes connection to the SQL server instantly.    
    *    
    *    Also should interrupt connections in progress.
    *
    *    Calls $(B callback) when closed.
    */
    void disconnect() nothrow
    in
    {
        assert(conn !is null, "Connection start wasn't established!");
    }
    body
    {
        conn.finish;
    }
    
    /**
    *   Returns SQL server name (domain) the connection is desired to connect to.
    *   If connection isn't ever established (or tried) the method returns empty string.
    */
    string server() nothrow const @property
    {
        scope(failure) return "";
        
        return conn.host;
    }
    
    private
    {
        bool reconnecting = false;
        shared ILogger logger;
        __gshared IPostgreSQL api;
        shared IPGconn conn;
        __gshared ConnectException savedException;
    }
    mixin Mockable!IConnection;
}

class PQConnProvider : IConnectionProvider
{
    this(shared ILogger logger, IPostgreSQL api)
    {
        this.logger = logger;
        this.api = api;
    }
    
    shared(IConnection) allocate()
    {
        return new shared PQConnection(logger, api);
    }
    
    private shared ILogger logger;
    private IPostgreSQL api;
}