// Written in D programming language
/**
*   Utilities for integration test of binary format conversion.
*
*   Copyright: © 2014 DSoftOut
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module db.pq.types.test;

version(IntegrationTest2):

import std.random;
import std.range;
import std.algorithm;
import std.encoding;
import std.traits;
import std.math;
import vibe.data.bson;
import derelict.pq.pq;
import db.pool;
import dlogg.log;
import dlogg.buffered;

T id(T)(T val) {return val;}

bool floatEquality(T)(T a, T b) 
    if(isFloatingPoint!T)
{
    if(a.isnan) return b.isnan;
    if(b.isnan) return a.isnan;
    return approxEqual(a,b);
}

Bson queryValue(shared ILogger logger, shared IConnectionPool pool, string val)
{
    auto query = "SELECT "~val~" as test_field";
    logger.logInfo(query);
    auto res = Bson.fromJson(pool.execTransaction([query]).front.toJson);
    
    logger.logInfo(text(res));
    return res.get!(Bson[string])["test_field"][0];
}

void testValue(T, alias converter = to!string, alias resConverter = id)
    (shared ILogger logger, shared IConnectionPool pool, T local, string sqlType)
{
	auto delayed = new shared BufferedLogger(logger);
	scope(exit) delayed.finalize();
	scope(failure) delayed.minOutputLevel = LoggingLevel.Notice;
	
    auto node = queryValue(delayed, pool, converter(local)~"::"~sqlType);
    
    static if(is(T == ubyte[]))
        auto remote = node.opt!BsonBinData.rawData;
    else 
        auto remote = node.deserializeBson!T;
        
    static if(isFloatingPoint!T)
    {
        assert(resConverter(remote).floatEquality(resConverter(local)), resConverter(remote).to!string ~ "!=" ~ resConverter(local).to!string);
    }
    else static if(isArray!T && isFloatingPoint!(ElementType!T))
    {
        assert(equal!floatEquality(resConverter(remote), resConverter(local)), resConverter(remote).to!string ~ "!=" ~ resConverter(local).to!string); 
    } else
    {
        assert(resConverter(remote) == resConverter(local), resConverter(remote).to!string ~ "!=" ~ resConverter(local).to!string);
    } 
}