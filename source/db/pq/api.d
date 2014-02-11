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