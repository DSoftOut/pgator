// Written in D programming language
/**
*   This module defines realization of high-level libpq api.
*
*   See_Also: db.pq.api
*
*   Copyright: © 2014 DSoftOut
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module pgator.db.pq.libpq;

public import pgator.db.pq.api;
public import derelict.pq.pq;
import derelict.util.exception;
import std.exception;
import std.string;
import std.regex;
import std.conv;
import core.memory;
import pgator.util.string;

synchronized class CPGresult : IPGresult
{
    this(PGresult* result) nothrow
    {
        results[this] = result;
    }
    
    /**
    *   Prototype: PQresultStatus
    */
    ExecStatusType resultStatus() nothrow const
    in
    {
        assert(this in results, "PGconn was finished!");
        assert(PQresultStatus !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        return PQresultStatus(results[this]);
    }
    
    /**
    *   Prototype: PQresStatus
    *   Note: same as resultStatus, but converts 
    *         the enum to human-readable string.
    */
    string resStatus() nothrow const
    in
    {
        assert(this in results, "PGconn was finished!");
        assert(PQresultStatus !is null, "DerelictPQ isn't loaded!");
        assert(PQresStatus !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        return fromStringz(PQresStatus(PQresultStatus(results[this])));
    }
    
    /**
    *   Prototype: PQresultErrorMessage
    */
    string resultErrorMessage() nothrow const
    in
    {
        assert(this in results, "PGconn was finished!");
        assert(PQresultErrorMessage !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        return fromStringz(PQresultErrorMessage(results[this]));
    }
    
    /**
    *   Prototype: PQclear
    */
    void clear() nothrow
    in
    {
        assert(this in results, "PGconn was finished!");
        assert(PQclear !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        PQclear(results[this]);
        results.remove(this);
    }
    
    /**
    *   Prototype: PQntuples
    */
    size_t ntuples() nothrow const
    in
    {
        assert(this in results, "PGconn was finished!");
        assert(PQntuples !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        return cast(size_t)PQntuples(results[this]);
    }
    
    /**
    *   Prototype: PQnfields
    */
    size_t nfields() nothrow const
    in
    {
        assert(this in results, "PGconn was finished!");
        assert(PQnfields !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        return cast(size_t)PQnfields(results[this]);
    }
    
    /**
    *   Prototype: PQfname
    */ 
    string fname(size_t colNumber) const
    in
    {
        assert(this in results, "PGconn was finished!");
        assert(PQfname !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        return enforceEx!RangeError(fromStringz(PQfname(results[this], cast(uint)colNumber)));
    }
    
    /**
    *   Prototype: PQfformat
    */
    bool isBinary(size_t colNumber) const
    in
    {
        assert(this in results, "PGconn was finished!");
        assert(PQfformat !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        return PQfformat(results[this], cast(uint)colNumber) == 1;
    }
    
    /**
    *   Prototype: PQgetvalue
    */
    string asString(size_t rowNumber, size_t colNumber) const
    in
    {
        assert(this in results, "PGconn was finished!");
        assert(PQgetvalue !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        import std.stdio; writeln(getLength(rowNumber, colNumber));
        return fromStringz(cast(immutable(char)*)PQgetvalue(results[this], cast(uint)rowNumber, cast(uint)colNumber));
    }
    
    /**
    *   Prototype: PQgetvalue
    */
    ubyte[] asBytes(size_t rowNumber, size_t colNumber) const
    in
    {
        assert(this in results, "PGconn was finished!");
        assert(PQgetvalue !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        auto l = getLength(rowNumber, colNumber);
        auto res = new ubyte[l];
        auto bytes = PQgetvalue(results[this], cast(uint)rowNumber, cast(uint)colNumber);
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
        assert(this in results, "PGconn was finished!");
        assert(PQgetisnull !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        return PQgetisnull(results[this], cast(uint)rowNumber, cast(uint)colNumber) != 0;
    }
    
    /**
    *   Prototype: PQgetlength
    */
    size_t getLength(size_t rowNumber, size_t colNumber) const
    in
    {
        assert(this in results, "PGconn was finished!");
        assert(PQgetisnull !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        return cast(size_t)PQgetlength(results[this], cast(uint)rowNumber, cast(uint)colNumber);
    }
    
    /**
    *   Prototype: PQftype
    */
    PQType ftype(size_t colNumber) const
    in
    {
        assert(this in results, "PGconn was finished!");
        assert(PQftype !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        return cast(PQType)PQftype(results[this], cast(uint)colNumber);
    }
    
    private __gshared PGresult*[shared const CPGresult] results;
}

synchronized class CPGconn : IPGconn
{
    this(PGconn* conn) nothrow
    {
        conns[this] = conn;
    }
    
    /**
    *   Prototype: PQconnectPoll
    */
    PostgresPollingStatusType poll() nothrow
    in
    {
        assert(this in conns, "PGconn was finished!");
        assert(PQconnectPoll !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        return PQconnectPoll(conns[this]);
    }
    
    /**
    *   Prototype: PQstatus
    */
    ConnStatusType status() nothrow
    in
    {
        assert(this in conns, "PGconn was finished!");
        assert(PQstatus !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        return PQstatus(conns[this]);
    }
    
    /**
    *   Prototype: PQfinish
    *   Note: this function should be called even
    *   there was an error.
    */
    void finish() nothrow
    in
    {
        assert(this in conns, "PGconn was finished!");
        assert(PQfinish !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        scope(failure) {}

        PQfinish(conns[this]);
        conns.remove(this);
    }
    
    /**
    *   Prototype: PQflush
    */
    bool flush() nothrow const
    in
    {
        assert(this in conns, "PGconn was finished!");
        assert(PQfinish !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        return PQflush(conns[this]) != 0;
    }
    
    /**
    *   Prototype: PQresetStart
    *   Throws: PGReconnectException
    */
    void resetStart()
    in
    {
        assert(this in conns, "PGconn was finished!");
        assert(PQresetStart !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        auto res = PQresetStart(conns[this]);
        if(res == 1)
            throw new PGReconnectException(errorMessage);
    }
    
    /**
    *   Prototype: PQresetPoll
    */
    PostgresPollingStatusType resetPoll() nothrow
    in
    {
        assert(this in conns, "PGconn was finished!");
        assert(PQresetPoll !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        return PQresetPoll(conns[this]);
    }
    
    /**
    *   Prototype: PQhost
    */
    string host() const nothrow @property
    in
    {
        assert(this in conns, "PGconn was finished!");
        assert(PQhost !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        scope(failure) return "";
        return fromStringz(PQhost(conns[this]));
    }    

    /**
    *   Prototype: PQdb
    */
    string db() const nothrow @property
    in
    {
        assert(this in conns, "PGconn was finished!");
        assert(PQdb !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        scope(failure) return "";
        return fromStringz(PQdb(conns[this]));
    }     

    /**
    *   Prototype: PQuser
    */
    string user() const nothrow @property
    in
    {
        assert(this in conns, "PGconn was finished!");
        assert(PQuser !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        scope(failure) return "";
        return fromStringz(PQuser(conns[this]));
    } 
    
    /**
    *   Prototype: PQport
    */
    string port() const nothrow @property
    in
    {
        assert(this in conns, "PGconn was finished!");
        assert(PQport !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        scope(failure) return "";
        return fromStringz(PQport(conns[this]));
    } 
    
    /**
    *   Prototype: PQerrorMessage
    */
    string errorMessage() const nothrow @property
    in
    {
        assert(this in conns, "PGconn was finished!");
        assert(PQerrorMessage !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        scope(failure) return "";
        return fromStringz(PQerrorMessage(conns[this]));
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
        assert(this in conns, "PGconn was finished!");
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
        auto res = PQsendQueryParams(conns[this], command.toStringz, cast(int)paramValues.length, null
            , toPlainArray(paramValues), null, null, 1);
        if (res == 0)
        {
            throw new PGQueryException(errorMessage);
        }
    }
    
    /**
    *   Prototype: PQsendQuery
    *   Throws: PGQueryException
    */
    void sendQuery(string command)
    in
    {
        assert(this in conns, "PGconn was finished!");
        assert(PQsendQuery !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        auto res = PQsendQuery(conns[this], command.toStringz);
        if (res == 0)
        {
            throw new PGQueryException(errorMessage);
        }
    }
    
    /**
    *   Like sendQueryParams but uses libpq escaping functions
    *   and sendQuery. 
    *   
    *   The main advantage of the function is ability to handle
    *   multiple SQL commands in one query.
    *   Throws: PGQueryException
    */
    void sendQueryParamsExt(string command, string[] paramValues)
    {
        try
        {
            sendQuery(escapeParams(command, paramValues));
        }
        catch(PGEscapeException e)
        {
            throw new PGQueryException(e.msg);
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
        assert(this in conns, "PGconn was finished!");
        assert(PQgetResult !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        auto res = PQgetResult(conns[this]);
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
        assert(this in conns, "PGconn was finished!");
        assert(PQconsumeInput !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        auto res = PQconsumeInput(conns[this]);
        if(res == 0) 
            throw new PGQueryException(errorMessage);
    }
    
    /**
    *   Prototype: PQisBusy
    */
    bool isBusy() nothrow
    in
    {
        assert(this in conns, "PGconn was finished!");
        assert(PQisBusy !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        return PQisBusy(conns[this]) > 0;
    }
    
    /**
    *   Prototype: PQescapeLiteral
    *   Throws: PGEscapeException
    */
    string escapeLiteral(string msg) const
    in
    {
        assert(this in conns, "PGconn was finished!");
        assert(PQescapeLiteral !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        auto res = PQescapeLiteral(conns[this], msg.toStringz, msg.length);
        if(res is null) throw new PGEscapeException(errorMessage);
        return fromStringz(res);
    }
    
    /**
    *   Escaping query like PQexecParams does. This function
    *   enables use of multiple SQL commands in one query.
    */
    private string escapeParams(string query, string[] args)
    {
        foreach(i, arg; args)
        {
            auto reg = regex(text(`\$`, i));
            query = query.replaceAll(reg, escapeLiteral(arg));
        }
        return query;
    }
    
    /**
    *   Prototype: PQparameterStatus
    *   Throws: PGParamNotExistException
    */
    string parameterStatus(string param) const
    in
    {
        assert(this in conns, "PGconn was finished!");
        assert(PQparameterStatus !is null, "DerelictPQ isn't loaded!");
    }
    body
    {
        // fix bindings char* -> const char*
        auto res = PQparameterStatus(conns[this], cast(char*)toStringz(param));
        if(res is null)
            throw new PGParamNotExistException(param);
        
        return res.fromStringz;
    }
    
    private __gshared PGconn*[shared const CPGconn] conns;
}

synchronized class PostgreSQL : IPostgreSQL
{
    this()
    {
        initialize();
    }
    
    /**
    *   Should be called to free libpq resources. The method
    *   unloads library from application memory.
    */
    void finalize() nothrow
    {
        scope(failure) {}
        GC.collect();
        DerelictPQ.unload();
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
                if( e.symbolName != "PQconninfo" &&
                    e.symbolName != "PQsetSingleRowMode")
                {
                    throw e;
                }
            }
        }
    }
}