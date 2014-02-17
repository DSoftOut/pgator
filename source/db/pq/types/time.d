// Written in D programming language
/**
*   PostgreSQL time types binary format.
*
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module db.pq.types.time;

import db.pq.types.oids;
import std.datetime;

struct Interval
{
    uint status;
    SysTime[2] data;
}

SysTime convert(PQType type)(ubyte[] val)
    if(type == PQType.AbsTime)
{
    assert(val.length == 4);
    return SysTime(cast(long)(cast(uint[])val)[0]);
}

SysTime convert(PQType type)(ubyte[] val)
    if(type == PQType.RelTime)
{
    assert(val.length == 4);
    return SysTime(cast(long)(cast(uint[])val)[0]);
}

Interval convert(PQType type)(ubyte[] val)
    if(type == PQType.Interval)
{
    assert(val.length == 12);
    Interval interval;
    interval.status = (cast(uint[])val)[0];
    interval.data[0] = SysTime((cast(uint[])val)[1]);
    interval.data[1] = SysTime((cast(uint[])val)[2]);
    return interval;
}

SysTime convert(PQType type)(ubyte[] val)
    if(type == PQType.TimeStamp || type == PQType.TimeStampWithZone)
{
    assert(val.length == 8);
    return SysTime((cast(long[])val)[0]);
}