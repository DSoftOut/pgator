// Written in D programming language
/**
*   PostgreSQL typed arrays binary data format.
*
*   Copyright: © 2014 DSoftOut
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module db.pq.types.array;

import db.pq.types.oids;
import derelict.pq.pq;
import std.array;
import std.bitmanip;
import std.conv;

private struct Vector(T)
{
    int     ndim;
    int     dataoffset;
    Oid     elemtype;
    int     dim1;
    int     lbound1;
    T[]     values;
}

private Vector!T readVec(T)(ubyte[] arr)
{
    if(arr.length == 0) return Vector!T();
    
    assert(arr.length >= 2*int.sizeof + Oid.sizeof, text(
            "Expected min array size ", 2*int.sizeof + Oid.sizeof, ", but got ", arr.length));
    Vector!T vec;
    
    vec.ndim    = arr.read!int;
    vec.dataoffset = arr.read!int;
    vec.elemtype   = arr.read!Oid;
    if(arr.length == 0) return vec;
    vec.dim1       = arr.read!int;
    vec.lbound1    = arr.read!int;
    
    static if(!is(T == string)) assert(arr.length % T.sizeof == 0);
    auto builder = appender!(T[]);
    while(arr.length > 0)
    {
        static if(is(T == string))
        {
            auto length = cast(size_t)arr.read!int;
            builder.put(cast(string)arr[0..length].idup);
            arr = arr[length .. $];
        } else
        {
            arr.read!int; // some kind of length
            builder.put(arr.read!T);
        }
    }
    vec.values = builder.data;
    return vec;    
}

short[] convert(PQType type)(ubyte[] val)
    if(type == PQType.Int2Vector || type == PQType.Int2Array)
{
    return val.readVec!short.values;
}

int[] convert(PQType type)(ubyte[] val)
    if(type == PQType.Int4Array)
{
    return val.readVec!int.values;
}

Oid[] convert(PQType type)(ubyte[] val)
    if(type == PQType.OidVector || type == PQType.OidArray)
{
    return val.readVec!Oid.values;
}

string[] convert(PQType type)(ubyte[] val)
    if(type == PQType.TextArray || type == PQType.CStringArray)
{
    return val.readVec!string.values;
}

float[] convert(PQType type)(ubyte[] val)
    if(type == PQType.Float4Array)
{
    return val.readVec!float.values;
}

version(IntegrationTest2)
{
    import db.pq.types.test;
    import db.pool;
    import std.array;
    import std.random;
    import std.math;
    import dlogg.log;
    
    string convertArray(T)(T[] ts)
    {
        auto builder = appender!string;
        foreach(i,t; ts)
        {
            static if(is(T == string)) builder.put("'");
            static if(is(T == float))
            {
               if(t == T.infinity) builder.put("'Infinity'");
               else if(t == -T.infinity) builder.put("'-Infinity'");
               else if(isnan(t)) builder.put("'NaN'");
               else builder.put(t.to!string);
            } else
            {
                builder.put(t.to!string);
            }
            static if(is(T == string)) builder.put("'");
            if(i != ts.length-1)
                builder.put(", ");
        }
        return "ARRAY["~builder.data~"]";
    } 
    
    T[] randArray(T)(size_t n)
    {
        auto builder = appender!(T[]);
        foreach(i; 0..n)
        {
            static if(is(T == string))
            {
                immutable alph = "1234567890asdfghjkklzxcvbnm,.?!@#$%^&*()+-|";
                auto zbuilder = appender!string;
                foreach(j; 0..uniform(0,100))
                    zbuilder.put(alph[uniform(0,alph.length)]);
                builder.put(zbuilder.data);
            } else static if(is(T == float))
            {
                builder.put(uniform(-1000.0, 1000.0));
            }
            else
            {
                builder.put(uniform(T.min, T.max));
            }
        }
        return builder.data;    
    }
    
    void testArray(T)(shared ILogger logger, shared IConnectionPool pool, string tname)
    {
        logger.logInfo("Testing "~tname~"...");
        foreach(i; 0..100)
            testValue!(T[], convertArray)(logger, pool, randArray!T(i), tname);
    }
        
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Int2Vector)
    { 
        testArray!short(logger, pool, "int2vector");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.OidVector)
    {       
        testArray!Oid(logger, pool, "oidvector");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.OidArray)
    {       
        testArray!Oid(logger, pool, "oid[]");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Int2Array)
    {
        testArray!short(logger, pool, "int2[]");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Int4Array)
    {
        testArray!int(logger, pool, "int4[]");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.TextArray)
    {
        testArray!string(logger, pool, "text[]");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.CStringArray)
    {
        testArray!string(logger, pool, "cstring[]");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Float4Array)
    {
        testArray!float(logger, pool, "float4[]"); 
        testValue!(float[], convertArray)(logger, pool, [float.infinity], "float4[]");
        testValue!(float[], convertArray)(logger, pool, [-float.infinity], "float4[]");
        testValue!(float[], convertArray)(logger, pool, [float.nan], "float4[]");
    }
}