// Written in D programming language
/**
*   This module defines realization of high-level libpq api.
*
*   See_Also: db.pq.api
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module db.pq.libpq;

public import db.pq.api;
public import derelict.pq.pq;
import derelict.util.exception;
import std.exception;
import std.string;
import core.atomic;
import util;

synchronized class CPGconn : IPGconn
{
    this(PGconn* conn)
    {
        this.conn = conn;
    }
    
    /**
    *   Prototype: PQconnectPoll
    */
    PostgresPollingStatusType poll() nothrow
    in
    {
        assert(conn !is null, "PGconn was finished!");
        assert(PQconnectPoll !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        return PQconnectPoll(conn);
    }
    
    /**
    *   Prototype: PQstatus
    */
    ConnStatusType status() nothrow
    in
    {
        assert(conn !is null, "PGconn was finished!");
        assert(PQstatus !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        return PQstatus(conn);
    }
    
    /**
    *   Prototype: PQfinish
    *   Note: this function should be called even
    *   there was an error.
    */
    void finish() nothrow
    in
    {
        assert(conn !is null, "PGconn was finished!");
        assert(PQfinish !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        PQfinish(conn);
        conn = null;
    }
    
    /**
    *   Prototype: PQresetStart
    *   Throws: PGReconnectException
    */
    void resetStart()
    in
    {
        assert(conn != null, "PGconn was finished!");
        assert(PQresetStart !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        auto res = PQresetStart(conn);
        if(res == 1)
            throw new PGReconnectException();
    }
    
    /**
    *   Prototype: PQresetPoll
    */
    PostgresPollingStatusType resetPoll() nothrow
    in
    {
        assert(conn !is null, "PGconn was finished!");
        assert(PQresetPoll !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        return PQresetPoll(conn);
    }
    
    /**
    *   Prototype: PQhost
    */
    string host() const nothrow @property
    in
    {
        assert(conn !is null, "PGconn was finished!");
        assert(PQhost !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        scope(failure) return "";
        return fromStringz(PQhost(cast()conn));
    }    

    /**
    *   Prototype: PQdb
    */
    string db() const nothrow @property
    in
    {
        assert(conn !is null, "PGconn was finished!");
        assert(PQdb !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        scope(failure) return "";
        return fromStringz(PQdb(cast()conn));
    }     

    /**
    *   Prototype: PQuser
    */
    string user() const nothrow @property
    in
    {
        assert(conn !is null, "PGconn was finished!");
        assert(PQuser !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        scope(failure) return "";
        return fromStringz(PQuser(cast()conn));
    } 
    
    /**
    *   Prototype: PQport
    */
    string port() const nothrow @property
    in
    {
        assert(conn !is null, "PGconn was finished!");
        assert(PQport !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        scope(failure) return "";
        return fromStringz(PQport(cast()conn));
    } 
    
    /**
    *   Prototype: PQerrorMessage
    */
    string errorMessage() const nothrow @property
    in
    {
        assert(conn !is null, "PGconn was finished!");
        assert(PQerrorMessage !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        scope(failure) return "";
        return fromStringz(PQerrorMessage(cast()conn));
    }
    
    private __gshared PGconn* conn;
}

class PostgreSQL : IPostgreSQL
{
    this()
    {
        initialize();
    }
    
    ~this()
    {
        shutdown();
    }
    
    /**
    *   Prototype: PQconnectStart
    *   Throws: PGMemoryLackException
    */
    shared(IPGconn) startConnect(string conninfo)
    in
    {
        assert(PQconnectStart !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        auto conn = enforceEx!PGMemoryLackException(PQconnectStart(cast(char*)conninfo.toStringz));
        return new shared CPGconn(conn);
    }
    
    protected
    {
        /**
        *   Should be called in class constructor. The method
        *   loads library in memory.
        */
        void initialize()
        {
            if(refCount > 0) return;
            scope(success) atomicOp!"+="(refCount, 1);
             
            version(linux)
            {
                try
                {
                    DerelictPQ.load();
                } catch(DerelictException e)
                {
                    // try with some frequently names
                    DerelictPQ.load("libpq.so.0 libpq.so.5");
                }
            }
            else
            {
                DerelictPQ.load();
            }
        }
        
        /**
        *   Should be called in class destructor. The method
        *   unloads library from memory.
        */
        void shutdown() nothrow
        {
            if(refCount <= 0) return;
            atomicOp!"-="(refCount, 1);
            
            if(refCount == 0)
            {
                scope(failure) {}
                DerelictPQ.unload();
            }
        }
    }
    private
    {
        shared uint refCount = 0;
    }
}