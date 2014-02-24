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

private void j2date(int jd, out int year, out int month, out int day)
{
    enum POSTGRES_EPOCH_JDATE = 2451545;
    enum MONTHS_PER_YEAR = 12;

    jd += POSTGRES_EPOCH_JDATE;
    
    uint julian = jd + 32044;
    uint quad = julian / 146097;
    uint extra = (julian - quad * 146097) * 4 + 3;
    julian += 60 + quad * 3 + extra / 146097;
    quad = julian / 1461;
    julian -= quad * 1461;
    int y = julian * 4 / 1461;
    julian = ((y != 0) ? ((julian + 305) % 365) : ((julian + 306) % 366))
        + 123;
    year = (y+ quad * 4) - 4800;
    quad = julian * 2141 / 65536;
    day = julian - 7834 * quad / 256;
    month = (quad + 10) % MONTHS_PER_YEAR + 1;
}

Date convert(PQType type)(ubyte[] val)
    if(type == PQType.Date)
{
    assert(val.length == uint.sizeof);
    uint raw = val.read!uint;
    int year, month, day;
    j2date(raw, year, month, day);
    
    return Date(year, month, day);
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
    import db.connection;
    import std.random;
    import std.algorithm;
    import std.encoding;
    import std.math;
    import vibe.data.bson;
    import log;
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Date)
    {
        logger.logInfo("================ Date ======================");
        auto dformat = pool.dateFormat;
        
        assert(queryValue(logger, pool, "'1999-01-08'::date").deserializeBson!Date.toISOExtString == "1999-01-08");
        assert(queryValue(logger, pool, "'January 8, 1999'::date").deserializeBson!Date.toISOExtString == "1999-01-08");
        assert(queryValue(logger, pool, "'1999-Jan-08'::date").deserializeBson!Date.toISOExtString == "1999-01-08");
        assert(queryValue(logger, pool, "'Jan-08-1999'::date").deserializeBson!Date.toISOExtString == "1999-01-08");
        assert(queryValue(logger, pool, "'08-Jan-1999'::date").deserializeBson!Date.toISOExtString == "1999-01-08");
        assert(queryValue(logger, pool, "'19990108'::date").deserializeBson!Date.toISOExtString == "1999-01-08");
        assert(queryValue(logger, pool, "'990108'::date").deserializeBson!Date.toISOExtString == "1999-01-08");
        assert(queryValue(logger, pool, "'1999.008'::date").deserializeBson!Date.toISOExtString == "1999-01-08");
        assert(queryValue(logger, pool, "'J2451187'::date").deserializeBson!Date.toISOExtString == "1999-01-08");
        assert(queryValue(logger, pool, "'January 8, 99 BC'::date").deserializeBson!Date.toISOExtString == "-0098-01-08");
           
        if(dformat.orderFormat == DateFormat.OrderFormat.MDY)
        {
            assert(queryValue(logger, pool, "'1/8/1999'::date").deserializeBson!Date.toISOExtString == "1999-01-08");
            assert(queryValue(logger, pool, "'1/18/1999'::date").deserializeBson!Date.toISOExtString == "1999-01-18");
            assert(queryValue(logger, pool, "'01/02/03'::date").deserializeBson!Date.toISOExtString == "2003-01-02");
            assert(queryValue(logger, pool, "'08-Jan-99'::date").deserializeBson!Date.toISOExtString == "1999-01-08");
            assert(queryValue(logger, pool, "'Jan-08-99'::date").deserializeBson!Date.toISOExtString == "1999-01-08");
        } 
        else if(dformat.orderFormat == DateFormat.OrderFormat.DMY)
        {
            assert(queryValue(logger, pool, "'1/8/1999'::date").deserializeBson!Date.toISOExtString == "1999-08-01");
            assert(queryValue(logger, pool, "'01/02/03'::date").deserializeBson!Date.toISOExtString == "2003-02-01");
            assert(queryValue(logger, pool, "'08-Jan-99'::date").deserializeBson!Date.toISOExtString == "1999-01-08");
            assert(queryValue(logger, pool, "'Jan-08-99'::date").deserializeBson!Date.toISOExtString == "1999-01-08");
        }
        else if(dformat.orderFormat == DateFormat.OrderFormat.YMD)
        {
            assert(queryValue(logger, pool, "'01/02/03'::date").deserializeBson!Date.toISOExtString == "2001-02-03");
            assert(queryValue(logger, pool, "'99-Jan-08'::date").deserializeBson!Date.toISOExtString == "1999-01-08");
        }

    }
    
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