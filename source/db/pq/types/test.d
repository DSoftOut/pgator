// Written in D programming language
/**
*   Utilities for integration test of binary format conversion.
*
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module db.pq.types.test;

version(IntegrationTest2):

import std.random;
import std.range;
import std.algorithm;
import std.encoding;
import vibe.data.bson;
import derelict.pq.pq;
import db.pool;
import log;

T id(T)(T val) {return val;}

void testValue(T, alias converter = to!string, alias resConverter = id)
    (shared ILogger logger, shared IConnectionPool pool, T local, string sqlType)
{
    string query;
    query = "SELECT "~converter(local)~"::"~sqlType~" as test_field";

    logger.logInfo(query);
    auto results = pool.execQuery(query, []).array;
    assert(results.length == 1);
    
    auto res = results[0];
    logger.logInfo(res.resultStatus.text);
    assert(res.resultStatus == ExecStatusType.PGRES_COMMAND_OK 
        || res.resultStatus == ExecStatusType.PGRES_TUPLES_OK, res.resultErrorMessage);
    
    logger.logInfo(text(results[0].asBson));
    auto node = results[0].asBson.get!(Bson[string])["test_field"][0];
    
    static if(is(T == ubyte[]))
        auto remote = node.opt!BsonBinData.rawData;
    else 
        auto remote = node.deserializeBson!T;
    assert(resConverter(remote) == resConverter(local), resConverter(remote).to!string ~ "!=" ~ resConverter(local).to!string); 
}