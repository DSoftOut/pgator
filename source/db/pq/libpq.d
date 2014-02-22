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
import core.memory;
import util;

synchronized class CPGresult : IPGresult
{
    this(PGresult* result) nothrow
    {
        this.result = result;
    }
    
    /**
    *   Prototype: PQresultStatus
    */
    ExecStatusType resultStatus() nothrow const
    in
    {
        assert(result !is null, "PGconn was finished!");
        assert(PQresultStatus !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        return PQresultStatus(result);
    }
    
    /**
    *   Prototype: PQresStatus
    *   Note: same as resultStatus, but converts 
    *         the enum to human-readable string.
    */
    string resStatus() nothrow const
    in
    {
        assert(result !is null, "PGconn was finished!");
        assert(PQresultStatus !is null, "DerelictPQ isn't loaded!");
        assert(PQresStatus !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        return fromStringz(PQresStatus(PQresultStatus(result)));
    }
    
    /**
    *   Prototype: PQresultErrorMessage
    */
    string resultErrorMessage() nothrow const
    in
    {
        assert(result !is null, "PGconn was finished!");
        assert(PQresultErrorMessage !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        return fromStringz(PQresultErrorMessage(result));
    }
    
    /**
    *   Prototype: PQclear
    */
    void clear() nothrow
    in
    {
        assert(result !is null, "PGconn was finished!");
        assert(PQclear !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        PQclear(result);
        result = null;
    }
    
    /**
    *   Prototype: PQntuples
    */
    size_t ntuples() nothrow const
    in
    {
        assert(result !is null, "PGconn was finished!");
        assert(PQntuples !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        return cast(size_t)PQntuples(result);
    }
    
    /**
    *   Prototype: PQnfields
    */
    size_t nfields() nothrow const
    in
    {
        assert(result !is null, "PGconn was finished!");
        assert(PQnfields !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        return cast(size_t)PQnfields(result);
    }
    
    /**
    *   Prototype: PQfname
    */ 
    string fname(size_t colNumber) const
    in
    {
        assert(result !is null, "PGconn was finished!");
        assert(PQfname !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        return enforceEx!RangeError(fromStringz(PQfname(result, cast(uint)colNumber)));
    }
    
    /**
    *   Prototype: PQfformat
    */
    bool isBinary(size_t colNumber) const
    in
    {
        assert(result !is null, "PGconn was finished!");
        assert(PQfformat !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        return PQfformat(result, cast(uint)colNumber) == 1;
    }
    
    /**
    *   Prototype: PQgetvalue
    */
    string asString(size_t rowNumber, size_t colNumber) const
    in
    {
        assert(result !is null, "PGconn was finished!");
        assert(PQgetvalue !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        import std.stdio; writeln(getLength(rowNumber, colNumber));
        return fromStringz(cast(immutable(char)*)PQgetvalue(result, cast(uint)rowNumber, cast(uint)colNumber));
    }
    
    /**
    *   Prototype: PQgetvalue
    */
    ubyte[] asBytes(size_t rowNumber, size_t colNumber) const
    in
    {
        assert(result !is null, "PGconn was finished!");
        assert(PQgetvalue !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        auto l = getLength(rowNumber, colNumber);
        auto res = new ubyte[l];
        auto bytes = PQgetvalue(result, cast(uint)rowNumber, cast(uint)colNumber);
        foreach(i; 0..l)
            res[i] = bytes[i];
        return res;
    }
    
    /**
    *   Prototype: PQgetisnull
    */
    bool getisnull(size_t rowNumber, size_t colNumber) const
    in
    {
        assert(result !is null, "PGconn was finished!");
        assert(PQgetisnull !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        return PQgetisnull(result, cast(uint)rowNumber, cast(uint)colNumber) != 0;
    }
    
    /**
    *   Prototype: PQgetlength
    */
    size_t getLength(size_t rowNumber, size_t colNumber) const
    in
    {
        assert(result !is null, "PGconn was finished!");
        assert(PQgetisnull !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        return cast(size_t)PQgetlength(result, cast(uint)rowNumber, cast(uint)colNumber);
    }
    
    /**
    *   Prototype: PQftype
    */
    PQType ftype(size_t colNumber) const
    in
    {
        assert(result !is null, "PGconn was finished!");
        assert(PQftype !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        return cast(PQType)PQftype(result, cast(uint)colNumber);
    }
    
    private __gshared PGresult* result;
}

synchronized class CPGconn : IPGconn
{
    this(PGconn* conn) nothrow
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
    
    /**
    *   Prototype: PQsendQueryParams
    *   Note: This is simplified version of the command that
    *         handles only string params.
    *   Throws: PGQueryException
    */
    void sendQueryParams(string command, string[] paramValues)
    in
    {
        assert(conn !is null, "PGconn was finished!");
        assert(PQsendQueryParams !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        const (ubyte)** toPlainArray(string[] arr)
        {
            auto ptrs = new char*[arr.length];
            foreach(i, ref p; ptrs)
                p = cast(char*) arr[i].toStringz;
            return cast(const(ubyte)**)ptrs.ptr;
        }
        // type error in bindings int -> size_t, const(char)* -> const(char*), const(ubyte)** -> const(ubyte**)
        auto res = PQsendQueryParams(conn, command.toStringz, cast(int)paramValues.length, null
            , toPlainArray(paramValues), null, null, 1);
        if (res == 0)
        {
            throw new PGQueryException(errorMessage);
        }
    }
    
    /**
    *   Prototype: PQgetResult
    *   Note: Even when PQresultStatus indicates a fatal error, 
    *         PQgetResult should be called until it returns a null pointer 
    *         to allow libpq to process the error information completely.
    *   Note: A null pointer is returned when the command is complete and t
    *         here will be no more results.
    */
    shared(IPGresult) getResult() nothrow
    in
    {
        assert(conn !is null, "PGconn was finished!");
        assert(PQgetResult !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        auto res = PQgetResult(conn);
        if(res is null) return null;
        return new shared CPGresult(res);
    }
    
    /**
    *   Prototype: PQconsumeInput
    *   Throws: PGQueryException
    */
    void consumeInput()
    in
    {
        assert(conn !is null, "PGconn was finished!");
        assert(PQconsumeInput !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        auto res = PQconsumeInput(conn);
        if(res == 0) 
            throw new PGQueryException(errorMessage);
    }
    
    /**
    *   Prototype: PQisBusy
    */
    bool isBusy() nothrow
    in
    {
        assert(conn !is null, "PGconn was finished!");
        assert(PQisBusy !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        return PQisBusy(conn) > 0;
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
             
            try
            {
                version(linux)
                {
                    try
                    {
                        DerelictPQ.load();
                    } catch(DerelictException e)
                    {
                        // try with some frequently names
                        DerelictPQ.load("libpq.so.0,libpq.so.5");
                    }
                }
                else
                {
                    DerelictPQ.load();
                }
            } catch(SymbolLoadException e)
            {
                if( e.symbolName != "PQconninfo" ||
                    e.symbolName != "PQsetSingleRowMode")
                {
                    throw e;
                }
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
                GC.collect();
                DerelictPQ.unload();
            }
        }
    }
    private
    {
        shared uint refCount = 0;
    }
}