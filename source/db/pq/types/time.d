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

version(Have_Int64_TimeStamp)
{
    private alias long TimeADT;
    private alias long TimeOffset;
}
else
{
    import std.math;
    
    private alias double TimeADT;
    private alias double TimeOffset;
    
    void TMODULO(ref double t, ref int q, double u)
    {
        q = cast(int)((t < 0) ? ceil(t / u) : floor(t / u));
        if (q != 0) t -= rint(q * u);
    }
    
    double TIMEROUND(double j) 
    {
        enum TIME_PREC_INV = 10000000000.0;
        return rint((cast(double) j) * TIME_PREC_INV) / TIME_PREC_INV;
    }
}

private TimeOfDay time2tm(TimeADT time)
{
    version(Have_Int64_TimeStamp)
    {
        immutable long USECS_PER_HOUR  = 3600000000;
        immutable long USECS_PER_MINUTE = 60000000;
        immutable long USECS_PER_SEC = 1000000;
        
        int tm_hour = cast(int)(time / USECS_PER_HOUR);
        time -= tm_hour * USECS_PER_HOUR;
        int tm_min = cast(int)(time / USECS_PER_MINUTE);
        time -= tm_min * USECS_PER_MINUTE;
        int tm_sec = cast(int)(time / USECS_PER_SEC);
        time -= tm_sec * USECS_PER_SEC;
        
        return TimeOfDay(tm_hour, tm_min, tm_sec);
    }
    else
    {    
        enum SECS_PER_HOUR = 3600;
        enum SECS_PER_MINUTE = 60;
        
        double      trem;
        int tm_hour, tm_min, tm_sec;
    recalc:
        trem = time;
        TMODULO(trem, tm_hour, cast(double) SECS_PER_HOUR);
        TMODULO(trem, tm_min, cast(double) SECS_PER_MINUTE);
        TMODULO(trem, tm_sec, 1.0);
        trem = TIMEROUND(trem);
        /* roundoff may need to propagate to higher-order fields */
        if (trem >= 1.0)
        {
            time = ceil(time);
            goto recalc;
        }
        return TimeOfDay(tm_hour, tm_min, tm_sec);
    }
}

/**
*   Wrapper around TimeOfDay to allow serializing to bson.
*/
struct PGTime
{
    int hour, minute, second;
    
    this(TimeOfDay tm) pure
    {
        hour = tm.hour;
        minute = tm.minute;
        second = tm.second;
    }
    
    T opCast(T)() const if(is(T == TimeOfDay))
    {
        return TimeOfDay(hour, minute, second);
    }
}

PGTime convert(PQType type)(ubyte[] val)
    if(type == PQType.Time)
{
    assert(val.length == 8);
    return PGTime(time2tm(val.read!TimeADT));
}

/**
*   Represents PostgreSQL Time with TimeZone.
*   Time zone is stored as UTC offset in seconds without DST.
*/
struct PGTimeWithZone
{
    int hour, minute, second, timeZoneOffset;
    
    this(TimeOfDay tm, const SimpleTimeZone tz) pure
    {
        hour = tm.hour;
        minute = tm.minute;
        second = tm.second;
        
        timeZoneOffset = cast(int)tz.utcOffset.dur!"minutes".total!"seconds";
    }
    
    T opCast(T)() const if(is(T == TimeOfDay))
    {
        return TimeOfDay(hour, minute, second);
    }
    
    T opCast(T)() const if(is(T == immutable SimpleTimeZone))
    {
        return new immutable SimpleTimeZone(dur!"seconds"(timeZoneOffset));
    }
}

PGTimeWithZone convert(PQType type)(ubyte[] val)
    if(type == PQType.TimeWithZone)
{
    assert(val.length == 12);
    return PGTimeWithZone(time2tm(val.read!TimeADT), new immutable SimpleTimeZone(-val.read!int.dur!"seconds"));
}

/**
*   PostgreSQL time interval isn't same with D std.datetime one.
*   It is simple Duration.
*
*   Consists of: microseconds $(B time), $(B day) count and $(B month) count.
*   Libpq uses different represantation for $(B time), but i store only 
*   in usecs format.
*/
private struct TimeInterval
{
    // in microseconds
    long        time;           /* all time units other than days, months and
                                 * years */
    int         day;            /* days, after time for alignment */
    int         month;          /* months and years, after time for alignment */
    
    this(ubyte[] arr)
    {
        assert(arr.length == TimeOffset.sizeof + 2*int.sizeof);
        version(Have_Int64_TimeStamp)
        {
            time  = arr.read!long;
        }
        else
        {
            time  = cast(long)(arr.read!double * 10e6);
        }
        
        day   = arr.read!int;
        month = arr.read!int;
    }
}

TimeInterval convert(PQType type)(ubyte[] val)
    if(type == PQType.TimeInterval)
{
    return TimeInterval(val);
}

/**
*   Wrapper around std.datetime.Interval to handle [de]serializing
*   acceptable for JSON-RPC and still conform with libpq format.
*
*   Note: libpq representation of abstime slightly different from
*   std.datetime, thats why time converted to string could differ
*   a lot for PostgreSQL and SysTime (about 9000-15000 seconds nonconstant 
*   offset). 
*/
struct PGInterval
{
    private Interval!SysTime interval;
    alias interval this;
    
    static PGInterval fromBson(Bson bson)
    {
        auto begin = SysTime(unixTimeToStdTime(bson.begin.get!long), UTC());
        auto end   = SysTime(unixTimeToStdTime(bson.end.get!long), UTC());
        return PGInterval(Interval!SysTime(begin, end));
    }
    
    Bson toBson() const
    {
        Bson[string] map;
        map["begin"] = Bson(cast(long)(interval.begin.toUnixTime));
        map["end"]   = Bson(cast(long)(interval.end.toUnixTime));
        return Bson(map);
    }
}

PGInterval convert(PQType type)(ubyte[] val)
    if(type == PQType.Interval)
{
    assert(val.length == 3*int.sizeof);
    auto state = val.read!int;
    auto beg = SysTime(unixTimeToStdTime(val.read!int), UTC());
    auto end = SysTime(unixTimeToStdTime(val.read!int), UTC());

    return PGInterval(Interval!SysTime(beg, end));
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
    import bufflog;
    
    void test(PQType type)(shared ILogger strictLogger, shared IConnectionPool pool)
        if(type == PQType.Date)
    {
        strictLogger.logInfo("Testing Date...");
        auto dformat = pool.dateFormat;
        auto logger = new shared BufferedLogger(strictLogger);
        scope(failure) logger.minOutputLevel = LoggingLevel.Notice;
        scope(exit) logger.finalize;
        
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
        logger.logInfo("Testing AbsTime...");
        
    }
     
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.RelTime)
    {
        logger.logInfo("Testing RelTime...");
    }
    
    void test(PQType type)(shared ILogger strictLogger, shared IConnectionPool pool)
        if(type == PQType.Time)
    {
        strictLogger.logInfo("Testing Time...");
        scope(failure) 
        {
            version(Have_Int64_TimeStamp) string s = "with Have_Int64_TimeStamp";
            else string s = "without Have_Int64_TimeStamp";
            
            strictLogger.logInfo("============================================");
            strictLogger.logInfo(text("Application was compiled ", s, ". Try to switch the compilation flag."));
            strictLogger.logInfo("============================================");
        }

        auto logger = new shared BufferedLogger(strictLogger);
        scope(failure) logger.minOutputLevel = LoggingLevel.Notice;
        scope(exit) logger.finalize;
        
        assert((cast(TimeOfDay)queryValue(logger, pool, "'04:05:06.789'::time").deserializeBson!PGTime).toISOExtString == "04:05:06");
        assert((cast(TimeOfDay)queryValue(logger, pool, "'04:05:06'::time").deserializeBson!PGTime).toISOExtString == "04:05:06");
        assert((cast(TimeOfDay)queryValue(logger, pool, "'04:05'::time").deserializeBson!PGTime).toISOExtString == "04:05:00");
        assert((cast(TimeOfDay)queryValue(logger, pool, "'040506'::time").deserializeBson!PGTime).toISOExtString == "04:05:06");
        assert((cast(TimeOfDay)queryValue(logger, pool, "'04:05 AM'::time").deserializeBson!PGTime).toISOExtString == "04:05:00");
        assert((cast(TimeOfDay)queryValue(logger, pool, "'04:05 PM'::time").deserializeBson!PGTime).toISOExtString == "16:05:00");
    }
    
    void test(PQType type)(shared ILogger strictLogger, shared IConnectionPool pool)
        if(type == PQType.TimeWithZone)
    {
        strictLogger.logInfo("Testing TimeWithZone...");
        scope(failure) 
        {
            version(Have_Int64_TimeStamp) string s = "with Have_Int64_TimeStamp";
            else string s = "without Have_Int64_TimeStamp";
            
            strictLogger.logInfo("============================================");
            strictLogger.logInfo(text("Application was compiled ", s, ". Try to switch the compilation flag."));
            strictLogger.logInfo("============================================");
        }
        
        auto logger = new shared BufferedLogger(strictLogger);
        scope(failure) logger.minOutputLevel = LoggingLevel.Notice;
        scope(exit) logger.finalize;
        
        auto res = queryValue(logger, pool, "'04:05:06.789-8'::time with time zone").deserializeBson!PGTimeWithZone;
        assert((cast(TimeOfDay)res).toISOExtString == "04:05:06" && (cast(immutable SimpleTimeZone)res).utcOffset.dur!"minutes".total!"hours" == -8);
        res = queryValue(logger, pool, "'04:05:06-08:00'::time with time zone").deserializeBson!PGTimeWithZone;
        assert((cast(TimeOfDay)res).toISOExtString == "04:05:06" && (cast(immutable SimpleTimeZone)res).utcOffset.dur!"minutes".total!"hours" == -8);
        res = queryValue(logger, pool, "'04:05-08:00'::time with time zone").deserializeBson!PGTimeWithZone;
        assert((cast(TimeOfDay)res).toISOExtString == "04:05:00" && (cast(immutable SimpleTimeZone)res).utcOffset.dur!"minutes".total!"hours" == -8);
        res = queryValue(logger, pool, "'040506-08'::time with time zone").deserializeBson!PGTimeWithZone;
        assert((cast(TimeOfDay)res).toISOExtString == "04:05:06" && (cast(immutable SimpleTimeZone)res).utcOffset.dur!"minutes".total!"hours" == -8);
        res = queryValue(logger, pool, "'04:05:06 PST'::time with time zone").deserializeBson!PGTimeWithZone;
        assert((cast(TimeOfDay)res).toISOExtString == "04:05:06" && (cast(immutable SimpleTimeZone)res).utcOffset.dur!"minutes".total!"hours" == -8);
        res = queryValue(logger, pool, "'2003-04-12 04:05:06 America/New_York'::time with time zone").deserializeBson!PGTimeWithZone;
        assert((cast(TimeOfDay)res).toISOExtString == "04:05:06" && (cast(immutable SimpleTimeZone)res).utcOffset.dur!"minutes".total!"hours" == -4);
    }
    
    void test(PQType type)(shared ILogger strictLogger, shared IConnectionPool pool)
        if(type == PQType.Interval)
    {
        strictLogger.logInfo("Testing tinterval...");
        scope(failure) 
        {
            version(Have_Int64_TimeStamp) string s = "with Have_Int64_TimeStamp";
            else string s = "without Have_Int64_TimeStamp";
            
            strictLogger.logInfo("============================================");
            strictLogger.logInfo(text("Application was compiled ", s, ". Try to switch the compilation flag."));
            strictLogger.logInfo("============================================");
        }
        
        auto logger = new shared BufferedLogger(strictLogger);
        scope(failure) logger.minOutputLevel = LoggingLevel.Notice;
        scope(exit) logger.finalize;
        
        auto res = queryValue(logger, pool, "'[\"Dec 20 20:45:53 1986 GMT\" \"Mar 8 03:14:04 2014 GMT\"]'::tinterval").deserializeBson!PGInterval;
        assert(res.begin == SysTime.fromSimpleString("1986-Dec-20 20:45:53Z"));
        assert(res.end   == SysTime.fromSimpleString("2014-Mar-08 03:14:04Z"));
        
        res = queryValue(logger, pool, "'[\"Dec 20 20:45:53 1986 +3\" \"Mar 8 03:14:04 2014 +3\"]'::tinterval").deserializeBson!PGInterval;
        assert(res.begin == SysTime.fromSimpleString("1986-Dec-20 20:45:53+03"));
        assert(res.end   == SysTime.fromSimpleString("2014-Mar-08 03:14:04+03"));

    }
    
    void test(PQType type)(shared ILogger strictLogger, shared IConnectionPool pool)
        if(type == PQType.TimeInterval)
    {
        strictLogger.logInfo("Testing TimeInterval...");
        scope(failure) 
        {
            version(Have_Int64_TimeStamp) string s = "with Have_Int64_TimeStamp";
            else string s = "without Have_Int64_TimeStamp";
            
            strictLogger.logInfo("============================================");
            strictLogger.logInfo(text("Application was compiled ", s, ". Try to switch the compilation flag."));
            strictLogger.logInfo("============================================");
        }
        
        auto logger = new shared BufferedLogger(strictLogger);
        scope(failure) logger.minOutputLevel = LoggingLevel.Notice;
        scope(exit) logger.finalize;
        
        auto res = queryValue(logger, pool, "'1-2'::interval").deserializeBson!TimeInterval;
        assert(res.time == 0 && res.day == 0 && res.month == 14);
        
        res = queryValue(logger, pool, "'3 4:05:06'::interval").deserializeBson!TimeInterval;
        assert(res.time.dur!"usecs" == 4.dur!"hours" + 5.dur!"minutes" + 6.dur!"seconds" && res.day == 3 && res.month == 0);
        
        res = queryValue(logger, pool, "'1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval").deserializeBson!TimeInterval;
        assert(res.time.dur!"usecs" == 4.dur!"hours" + 5.dur!"minutes" + 6.dur!"seconds" && res.day == 3 && res.month == 14);
        
        res = queryValue(logger, pool, "'P1Y2M3DT4H5M6S'::interval").deserializeBson!TimeInterval;
        assert(res.time.dur!"usecs" == 4.dur!"hours" + 5.dur!"minutes" + 6.dur!"seconds" && res.day == 3 && res.month == 14);
        
        res = queryValue(logger, pool, "'P0001-02-03T04:05:06'::interval").deserializeBson!TimeInterval;
        assert(res.time.dur!"usecs" == 4.dur!"hours" + 5.dur!"minutes" + 6.dur!"seconds" && res.day == 3 && res.month == 14);
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.TimeStamp)
    {
        logger.logInfo("Testing TimeStamp...");
    }
     
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.TimeStampWithZone)
    {
        logger.logInfo("Testing TimeStampWithZone...");
    }
}