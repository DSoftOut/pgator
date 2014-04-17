// Written in D programming language
/**
*   Module describes a real connection to PostgreSQL server.
*
*   Copyright: © 2014 DSoftOut
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module db.pq.connection;

import dunit.mockable;
import derelict.pq.pq;
import db.connection;
import db.pq.api;
import dlogg.log;
import std.algorithm;
import std.conv;
import std.container;
import std.range;
import std.datetime;
import vibe.data.bson;

/**
*   PostgreSQL specific connection type. Although it can use
*   different data base backend, the class is defined to 
*   support only PostgreSQL.
*/
synchronized class PQConnection : IConnection
{
    this(shared ILogger logger, shared IPostgreSQL api)
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
            lastConnString = connString;
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
            /// reset cannot reset connection with restarted postgres server
            /// replaced with plain connect for now
            /// see issue #57 fo more info
            //conn.resetStart();
            //reconnecting = true;
            
            conn = api.startConnect(lastConnString);
            reconnecting = false;
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
        if(this in savedExceptions)
            savedExceptions.remove(this);
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
                        savedExceptions[this] = new ConnectException(server, "Connection wasn't tried to be established!");
                        return ConnectionStatus.Error;
                    }
                    case(ConnStatusType.CONNECTION_BAD):
                    {
                        savedExceptions[this] = new ConnectException(server, conn.errorMessage);
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
                savedExceptions[this] = new ConnectException(server, conn.errorMessage);
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
        if(this in savedExceptions) throw savedExceptions[this];
    }
    
    /**
    *   Initializes querying process in non-blocking manner.
    *   Throws: QueryException
    */
    void postQuery(string com, string[] params = [])
    in
    {
        assert(conn !is null, "Connection start wasn't established!");
    }
    body
    {
        try conn.sendQueryParams(com, params);
        catch (PGQueryException e)
        {
            throw new QueryException(e.msg);
        }
    }
    
    /**
    *   Returns quering status of connection.
    */
    QueringStatus pollQueringStatus() nothrow
    in
    {
        assert(conn !is null, "Connection start wasn't established!");
    }
    body
    {
        if(this in savedQueryExceptions)
            savedQueryExceptions.remove(this);
        try conn.consumeInput();
        catch (Exception e) // PGQueryException
        {
            savedQueryExceptions[this] = new QueryException(e.msg);
            while(conn.getResult !is null) {}
            return QueringStatus.Error;
        }
        
        if(conn.isBusy) return QueringStatus.Pending;
        else return QueringStatus.Finished;
    }
    
    /**
    *   Sending senseless query to the server to check if the connection is
    *   actually alive (e.g. nothing can detect fail after postgresql restart but
    *   query).
    */    
    bool testAlive() nothrow
    {
        try
        {
            auto reses = execQuery("SELECT 'pgator_ping';");
            foreach(res; reses)
            {
                res.clear();
            }
        } catch(Exception e)
        {
            return false;
        }
        return true;
    }
    
    /**
    *   If quering process is ended with error state, then
    *   throws QueryException, else do nothing.
    *
    *   Throws: QueryException
    */
    void pollQueryException()
    {
        if (this in savedQueryExceptions) throw savedQueryExceptions[this];
    }
    
    /**
    *   Returns query result, if $(B pollQueringStatus) shows that
    *   query is processed without errors, else blocks the caller
    *   until the answer is arrived.
    */
    DList!(shared IPGresult) getQueryResult()
    in
    {
        assert(conn !is null, "Connection start wasn't established!");
    }
    body
    {
        if(conn.isBusy)
        {
            while(pollQueringStatus != QueringStatus.Finished) pollQueryException();
        }
        
        DList!(shared IPGresult) resList;
        shared IPGresult res = conn.getResult;
        while(res !is null) 
        {
            resList.insert(res);
            res = conn.getResult;
        }
        
        return resList;
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
        scope(failure) {}
        conn.finish;
        conn = null;
        if(this in savedExceptions)
            savedExceptions.remove(this);
        if(this in savedQueryExceptions)
            savedQueryExceptions.remove(this);
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
    
    /**
    *   Returns current date output format and ambitious values converting behavior.
    *   Throws: QueryException
    */
    DateFormat dateFormat() @property
    {
        auto result = execQuery("SHOW DateStyle;").array;
        
        if(result.length == 0) throw new QueryException("DateFormat query expected result!");
        
        auto res = result[0].asColumnBson(this)["DateStyle"].deserializeBson!(string[]);
        assert(res.length == 1);
        auto vals = res[0].split(", ");
        assert(vals.length == 2);
        return DateFormat(vals[0], vals[1]);
    }
    
    /**
    *   Returns actual timestamp representation format used in server.
    *
    *   Note: This property tells particular HAVE_INT64_TIMESTAMP version flag that is used
    *         by remote server.
    */
    TimestampFormat timestampFormat() @property
    {
        try
        {
            auto res = conn.parameterStatus("integer_datetimes");
            if(res == "on")
            {
                return TimestampFormat.Int64;
            } else
            {
                return TimestampFormat.Float8;
            }
        } catch(PGParamNotExistException e)
        {
            logger.logInfo(text("Server doesn't support '", e.param,"' parameter! Assume HAVE_INT64_TIMESTAMP."));
            return TimestampFormat.Int64; 
        }
    }
    
    /**
    *   Returns server time zone. This value is important to handle 
    *   time stamps with time zone specified as libpq doesn't send
    *   the information with time stamp.
    *
    *   Note: Will fallback to UTC value if server protocol doesn't support acquiring of
    *         'TimeZone' parameter or server returns invalid time zone name.
    */
    immutable(TimeZone) timeZone() @property
    {
        try
        {
            auto res = conn.parameterStatus("TimeZone");

            try
            {
                return TimeZone.getTimeZone(res);
            } catch(DateTimeException e)
            {
                logger.logInfo(text("Cannot parse time zone value '", res, "'. Assume UTC."));
                return UTC();
            }

        } catch(PGParamNotExistException e)
        {
            logger.logInfo(text("Server doesn't support '", e.param,"' parameter! Assume UTC."));
            return UTC(); 
        }
    }
    
    private
    {
        bool reconnecting = false;
        string lastConnString;
        shared ILogger logger;
        shared IPostgreSQL api;
        shared IPGconn conn;
        __gshared ConnectException[shared PQConnection] savedExceptions;
        __gshared QueryException[shared PQConnection]   savedQueryExceptions;
    }
    mixin Mockable!IConnection;
}

synchronized class PQConnProvider : IConnectionProvider
{
    this(shared ILogger logger, shared IPostgreSQL api)
    {
        this.logger = logger;
        this.api = api;
    }
    
    shared(IConnection) allocate()
    {
        return new shared PQConnection(logger, api);
    }
    
    private shared ILogger logger;
    private shared IPostgreSQL api;
}
