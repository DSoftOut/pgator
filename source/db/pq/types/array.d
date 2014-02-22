// Written in D programming language
/**
*   PostgreSQL typed arrays binary data format.
*
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
    
    assert(arr.length >= 2*int.sizeof + Oid.sizeof, text(
            "Expected min array size ", 2*int.sizeof + Oid.sizeof, ", but got ", arr.length));
    Vector!T vec;
    
    vec.ndim    = arr.read!int;
    vec.dataoffset = arr.read!int;
    vec.elemtype   = arr.read!Oid;
    if(arr.length == 0) return vec;
    vec.dim1       = arr.read!int;
    vec.lbound1    = arr.read!int;
    
    assert(arr.length % T.sizeof == 0);
    auto builder = appender!(T[]);
    while(arr.length > 0)
    {
        arr.read!int; // some kind of length
        builder.put(arr.read!T);
    }
    vec.values = builder.data;
    import std.stdio; writeln(vec.values);
    return vec;    
}

short[] convert(PQType type)(ubyte[] val)
    if(type == PQType.Int2Vector)
{
    return val.readVec!short.values;
}

Oid[] convert(PQType type)(ubyte[] val)
    if(type == PQType.OidVector)
{
    return val.readVec!Oid.values;
}

version(IntegrationTest2)
{
    import db.pq.types.test;
    import db.pool;
    import std.array;
    import std.random;
    import log;
    
    string convertArray(T)(T[] ts)
    {
        auto builder = appender!string;
        foreach(i,t; ts)
        {
            builder.put(t.to!string);
            if(i != ts.length-1)
                builder.put(", ");
        }
        return "ARRAY["~builder.data~"]";
    } 
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Int2Vector)
    {
        short[] genRand(size_t n)
        {
            auto builder = appender!(short[]);
            foreach(i; 0..n)
                builder.put(uniform(short.min, short.max));
            return builder.data;    
        }
        
        logger.logInfo("================ Int2Vector ======================");
        foreach(i; 0..100)
            testValue!(short[], convertArray)(logger, pool, genRand(i), "int2vector");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.OidVector)
    {
        Oid[] genRand(size_t n)
        {
            auto builder = appender!(Oid[]);
            foreach(i; 0..n)
                builder.put(uniform(Oid.min, Oid.max));
            return builder.data;    
        }
        
        logger.logInfo("================ OidVector ======================");
        logger.logInfo("Enable this test after vibe.d issue #538 be fixed");
//        foreach(i; 0..100)
//            testValue!(Oid[], convertArray)(logger, pool, genRand(i), "oidvector");
    }
}