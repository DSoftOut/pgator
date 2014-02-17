// Written in D programming language
/**
*   This module defines high-level wrapper around libpq bindings.
*
*   The major goals:
*   <ul>
*       <li>Get more control over library errors (by converting to exceptions)</li>
*       <li>Create layer that can be mocked in purpose of unittesting</li>
*   </ul>
*
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module db.pq.api;

import derelict.pq.pq;
public import db.pq.types.oids;
import db.pq.types.conv;
import vibe.data.bson;

/**
*   All exceptions thrown by postgres api is inherited from this exception.
*/
class PGException : Exception
{
    @safe pure nothrow this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line); 
    }
}

/**
*   The exception is thrown when libpq ran in out of memory problems.
*/
class PGMemoryLackException : PGException
{
    @safe pure nothrow this(string file = __FILE__, size_t line = __LINE__)
    {
        super("PostgreSQL API: not enough memory!", file, line); 
    }
}

/**
*   The exception is thrown when PGconn has a problem with reconnecting process.
*/
class PGReconnectException : PGException
{
    @safe pure nothrow this(string file = __FILE__, size_t line = __LINE__)
    {
        super("PostgreSQL API: failed to reconnect to SQL server!", file, line); 
    }
}

/**
*   The exception is thrown when postgres ran in problem with query processing.
*/
class PGQueryException : PGException
{
    @safe pure nothrow this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line); 
    }
}

/**
*   Prototype: PGResult
*/
interface IPGresult
{
    synchronized:
    
    /**
    *   Prototype: PQresultStatus
    */
    ExecStatusType resultStatus() nothrow const;
    
    /**
    *   Prototype: PQresStatus
    *   Note: same as resultStatus, but converts 
    *         the enum to human-readable string.
    */
    string resStatus() nothrow const;
    
    /**
    *   Prototype: PQresultErrorMessage
    */
    string resultErrorMessage() nothrow const;
    
    /**
    *   Prototype: PQclear
    */
    void clear() nothrow;
    
    /**
    *   Prototype: PQntuples
    */
    size_t ntuples() const nothrow;

    /**
    *   Prototype: PQnfields
    */
    size_t nfields() const nothrow;
        
    /**
    *   Prototype: PQfname
    */ 
    string fname(size_t colNumber) const;
    
    /**
    *   Prototype: PQfformat
    */
    bool isBinary(size_t colNumber) const;
    
    /**
    *   Prototype: PQgetvalue
    */
    string asString(size_t rowNumber, size_t colNumber) const;
    
    /**
    *   Prototype: PQgetvalue
    */
    ubyte[] asBytes(size_t rowNumber, size_t colNumber) const;
    
    /**
    *   Prototype: PQgetisnull
    */
    bool getisnull(size_t rowNumber, size_t colNumber) const;
    
    /**
    *   Prototype: PQgetlength
    */
    size_t getLength(size_t rowNumber, size_t colNumber) const;
    
    /**
    *   Prototype: PQftype
    */
    PQType ftype(size_t colNumber) const;
    
    final Bson asBson()
    {
        Bson[string] fields;
        foreach(i; 0..nfields)
        {
            Bson[] rows;
            foreach(j; 0..ntuples)
            {
                rows ~= pqToBson(ftype(i), asBytes(j, i));
            }
            fields[fname(i)] = Bson(rows);
        }
        
        return Bson(fields);
    }
}

/**
*   Prototype: PGconn
*/
interface IPGconn
{
    synchronized:
    
    /**
    *   Prototype: PQconnectPoll
    */
    PostgresPollingStatusType poll() nothrow;
    
    /**
    *   Prototype: PQstatus
    */
    ConnStatusType status() nothrow;
    
    /**
    *   Prototype: PQfinish
    *   Note: this function should be called even
    *   there was an error.
    */
    void finish() nothrow;
    
    /**
    *   Prototype: PQresetStart
    *   Throws: PGReconnectException
    */
    void resetStart();
    
    /**
    *   Prototype: PQresetPoll
    */
    PostgresPollingStatusType resetPoll() nothrow;
    
    /**
    *   Prototype: PQhost
    */
    string host() const nothrow @property;

    /**
    *   Prototype: PQdb
    */
    string db() const nothrow @property;

    /**
    *   Prototype: PQuser
    */
    string user() const nothrow @property;
    
    /**
    *   Prototype: PQport
    */
    string port() const nothrow @property;
    
    /**
    *   Prototype: PQerrorMessage
    */
    string errorMessage() const nothrow @property;
    
    /**
    *   Prototype: PQsendQueryParams
    *   Note: This is simplified version of the command that
    *         handles only string params.
    *   Throws: PGQueryException
    */
    void sendQueryParams(string command, string[] paramValues); 
    
    /**
    *   Prototype: PQgetResult
    *   Note: Even when PQresultStatus indicates a fatal error, 
    *         PQgetResult should be called until it returns a null pointer 
    *         to allow libpq to process the error information completely.
    *   Note: A null pointer is returned when the command is complete and t
    *         here will be no more results.
    */
    shared(IPGresult) getResult() nothrow;
    
    /**
    *   Prototype: PQconsumeInput
    *   Throws: PGQueryException
    */
    void consumeInput();
    
    /**
    *   Prototype: PQisBusy
    */
    bool isBusy() nothrow;
}

/**
*   OOP styled libpq wrapper to automatically handle library loading/unloading and
*   to provide mockable layer for unittests. 
*/
interface IPostgreSQL
{
    /**
    *   Prototype: PQconnectStart
    *   Throws: PGMemoryLackException
    */
    shared(IPGconn) startConnect(string conninfo);
    
    protected
    {
        /**
        *   Should be called in class constructor. The method
        *   loads library in memory.
        */
        void initialize();
        
        /**
        *   Should be called in class destructor. The method
        *   unloads library from memory.
        */
        void shutdown() nothrow;
    }
}