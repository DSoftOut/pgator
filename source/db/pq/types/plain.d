// Written in D programming language
/**
*   PostgreSQL common types binary format.
*
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module db.pq.types.plain;

import db.pq.types.oids;
import vibe.data.json;
import std.numeric;
import std.array;
import std.bitmanip;
import std.format;
import std.conv;
import util;

alias ushort RegProc;
alias ushort Oid;
alias uint Xid;
alias uint Cid;

struct PQTid
{
    uint blockId, blockNumber;
}

bool convert(PQType type)(ubyte[] val)
    if(type == PQType.Bool)
{
    assert(val.length == 1);
    return val[0] != 0;
}

/**
*   Converts byte array into hex escaped SQL byte array.
*/
string escapeBytea(const ubyte[] arr)
{
    auto builder = appender!string;
    foreach(b; arr)
        formattedWrite(builder, "%02X", b);
    
    return `E'\\x`~builder.data~"'"; 
}

ubyte[] convert(PQType type)(ubyte[] val)
    if(type == PQType.ByteArray)
{
    return val.dup;
}

char convert(PQType type)(ubyte[] val)
    if(type == PQType.Char)
{
    assert(val.length == 1);
    return cast(char)val[0];
}

string convert(PQType type)(ubyte[] val)
    if(type == PQType.Name)
{
    assert(val.length == 63, text("Expected 63 bytes for name, but there are ", val.length, " bytes!"));
    return cast(string)val.idup;
}

long convert(PQType type)(ubyte[] val)
    if(type == PQType.Int8)
{
    assert(val.length == 8);
    return (cast(long[])val)[0];
}

short convert(PQType type)(ubyte[] val)
    if(type == PQType.Int2)
{
    assert(val.length == 2);
    return (cast(short[])val)[0];
}

short[] convert(PQType type)(ubyte[] val)
    if(type == PQType.Int2Vector)
{
    assert(val.length % 2 == 0);
    return (cast(short[])val).dup;
}

int convert(PQType type)(ubyte[] val)
    if(type == PQType.Int4)
{
    assert(val.length == 4);
    return (cast(int[])val)[0];
}

RegProc convert(PQType type)(ubyte[] val)
    if(type == PQType.RegProc)
{
    assert(val.length == 4);
    return (cast(ushort[])val)[0];
}

string convert(PQType type)(ubyte[] val)
    if(type == PQType.Text)
{
    assert(val.length > 0);
    return fromStringz(cast(char*)val.ptr);
}

Oid convert(PQType type)(ubyte[] val)
    if(type == PQType.Oid)
{
    assert(val.length == 2);
    return (cast(ushort[])val)[0];
}

PQTid convert(PQType type)(ubyte[] val)
    if(type == PQType.Tid)
{
    assert(val.length == 8);
    PQTid res;
    res.blockId = (cast(uint[])val)[0];
    res.blockNumber = (cast(uint[])val)[1];
    return res;
}

Xid convert(PQType type)(ubyte[] val)
    if(type == PQType.Xid)
{
    assert(val.length == 4);
    return (cast(uint[])val)[0];
}

Cid convert(PQType type)(ubyte[] val)
    if(type == PQType.Cid)
{
    assert(val.length == 4);
    return (cast(uint[])val)[0];
}

Oid[] convert(PQType type)(ubyte[] val)
    if(type == PQType.OidVec)
{
    assert(val.length % 2);
    return (cast(ushort[])val).dup;
}

Json convert(PQType type)(ubyte[] val)
    if(type == PQType.Json)
{
    string payload = fromStringz(cast(char*)val.ptr);
    return parseJsonString(payload);
}

string convert(PQType type)(ubyte[] val)
    if(type == PQType.Xml)
{
    assert(val.length > 0);
    return fromStringz(cast(char*)val.ptr);
}

string convert(PQType type)(ubyte[] val)
    if(type == PQType.NodeTree)
{
    assert(val.length > 0);
    return fromStringz(cast(char*)val.ptr);
}

float convert(PQType type)(ubyte[] val)
    if(type == PQType.Float4)
{
    assert(val.length == 1);
    static assert((CustomFloat!8).sizeof == 1);
    CustomFloat!8 v = (cast(CustomFloat!8[])val)[0];
    return cast(float)v;
}

float convert(PQType type)(ubyte[] val)
    if(type == PQType.Float8)
{
    assert(val.length == 1);
    return (cast(float[])val)[0];
}

string convert(PQType type)(ubyte[] val)
    if(type == PQType.Unknown)
{
    return convert!(PQType.Text)(val);
}

long convert(PQType type)(ubyte[] val)
    if(type == PQType.Money)
{
    assert(val.length == 8);
    return (cast(long[])val)[0];
}

version(IntegrationTest2)
{
    import db.pool;
    import std.random;
    import std.range;
    import std.algorithm;
    import std.encoding;
    import vibe.data.bson;
    import derelict.pq.pq;
    import log;
    
    T id(T)(T val) {return val;}
    
    void testValue(T, alias converter = to!string, alias resConverter = id)
        (shared ILogger logger, IConnectionPool pool, T local, string sqlType)
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
            auto remote = node.get!T;
        assert(resConverter(remote) == resConverter(local), resConverter(remote).to!string ~ "!=" ~ resConverter(local).to!string); 
    }
        
    void test(PQType type)(shared ILogger logger, IConnectionPool pool)
        if(type == PQType.Bool)
    {
        logger.logInfo("================ Bool ======================");
        testValue!bool(logger, pool, true, "boolean");
        testValue!bool(logger, pool, false, "boolean");
    }
    
    void test(PQType type)(shared ILogger logger, IConnectionPool pool)
        if(type == PQType.ByteArray)
    {
        ubyte[] genRand(size_t n)
        {
            auto builder = appender!(ubyte[]);
            foreach(i; 0..n)
                builder.put(cast(ubyte)uniform(0u, 255u));
            return builder.data; 
        }
        
        logger.logInfo("================ ByteArray ======================");
        foreach(i; 0..100)
            testValue!(ubyte[], escapeBytea)(logger, pool, genRand(i), "bytea");

    }
    
    void test(PQType type)(shared ILogger logger, IConnectionPool pool)
        if(type == PQType.Char)
    {
        logger.logInfo("================ Char ======================");
        alias testValue!(string, to!string, (str) {
                str = str.strip('\'');
                return str == `\` ? `\0` : str;}) test;
        
        test(logger, pool, `'\0'`, `"char"`);
        test(logger, pool, `''''`, `"char"`);
        foreach(char c; char.min .. char.max)
            if((['\0', '\'']).find(c).empty && isValid(`'`~c~`'`))
                test(logger, pool, `'`~c~`'`, `"char"`);
        
    }
    
    void test(PQType type)(shared ILogger logger, IConnectionPool pool)
        if(type == PQType.Name)
    {
        logger.logInfo("================ Name ======================");
        
        string genRand()
        {
            auto builder = appender!string;
            immutable aphs = "1234567890qwertyuiopasdfghjklzxcvbnm";
            foreach(i; 0..63)
                builder.put(aphs[uniform(0, aphs.length)]);
            return builder.data;    
        }
        
        foreach(i; 0..100)
            testValue!(string, to!string, (str) => str.strip('\''))(logger, pool, `'`~genRand()~`'`, "name");
    }
}