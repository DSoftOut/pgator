// Written in D programming language
/**
*   PostgreSQL time types binary format.
*
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module db.pq.types.time;

import db.pq.types.oids;
import std.datetime;
import std.bitmanip;

struct Interval
{
    uint status;
    SysTime[2] data;
}

SysTime convert(PQType type)(ubyte[] val)
    if(type == PQType.AbsTime || type == PQType.RelTime)
{
    assert(val.length == 8);
    return SysTime(val.read!long);
}

Interval convert(PQType type)(ubyte[] val)
    if(type == PQType.Interval)
{
    assert(val.length == 12);
    Interval interval;
    interval.status = val.read!uint;
    interval.data[0] = SysTime(val.read!uint);
    interval.data[1] = SysTime(val.read!uint);
    return interval;
}

SysTime convert(PQType type)(ubyte[] val)
    if(type == PQType.TimeStamp || type == PQType.TimeStampWithZone)
{
    assert(val.length == 8);
    return SysTime(val.read!long);
}

version(IntegrationTest2)
{
    import db.pq.types.test;
    import db.pool;
    import std.random;
    import std.algorithm;
    import std.encoding;
    import std.math;
    import log;
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.AbsTime)
    {
        logger.logInfo("================ AbsTime ======================");
    }
     
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.RelTime)
    {
        logger.logInfo("================ RelTime ======================");
    }
     
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Interval)
    {
        logger.logInfo("================ Interval ======================");
    }
     
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.TimeStamp)
    {
        logger.logInfo("================ TimeStamp ======================");
    }
     
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.TimeStampWithZone)
    {
        logger.logInfo("================ TimeStampWithZone ======================");
    }
}