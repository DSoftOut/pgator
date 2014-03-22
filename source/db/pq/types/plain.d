// Written in D programming language
/**
*   PostgreSQL common types binary format.
*
*   Copyright: © 2014 DSoftOut
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module db.pq.types.plain;

import db.pq.types.oids;
import vibe.data.json;
import std.array;
import std.bitmanip;
import std.format;
import std.conv;
import util;

alias uint RegProc;
alias uint Oid;
alias uint Xid;
alias uint Cid;

struct PQTid
{
    uint blockId, blockNumber;
    
    string toString() const
    {
        return text("'(",blockId, ",", blockNumber, ")'");
    }
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
    assert(val.length == 1, text("Expected 1 bytes, but got ", val.length));
    return val.read!char;
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
    assert(val.length == 8, text("Expected 8 bytes, but got ", val.length));
    return val.read!long;
}

short convert(PQType type)(ubyte[] val)
    if(type == PQType.Int2)
{
    assert(val.length == 2, text("Expected 2 bytes, but got ", val.length));
    return val.read!short;
}

int convert(PQType type)(ubyte[] val)
    if(type == PQType.Int4)
{
    assert(val.length == 4, text("Expected 4 bytes, but got ", val.length));
    return val.read!int;
}

RegProc convert(PQType type)(ubyte[] val)
    if(type == PQType.RegProc)
{
    assert(val.length == 4, text("Expected 4 bytes, but got ", val.length));
    return val.read!RegProc;
}

string convert(PQType type)(ubyte[] val)
    if(type == PQType.Text || type == PQType.FixedString || type == PQType.VariableString)
{
    return cast(string)val.idup;
}

Oid convert(PQType type)(ubyte[] val)
    if(type == PQType.Oid)
{
    assert(val.length == Oid.sizeof);
    return val.read!Oid;
}

PQTid convert(PQType type)(ubyte[] val)
    if(type == PQType.Tid)
{
    assert(val.length == 8, text("Expected 8 bytes, but got ", val.length));
    PQTid res;
    res.blockId = val.read!uint;
    res.blockNumber = val.read!uint;
    return res;
}

Xid convert(PQType type)(ubyte[] val)
    if(type == PQType.Xid)
{
    assert(val.length == 4, text("Expected 4 bytes, but got ", val.length));
    return val.read!uint;
}

Cid convert(PQType type)(ubyte[] val)
    if(type == PQType.Cid)
{
    assert(val.length == 4, text("Expected 4 bytes, but got ", val.length));
    return val.read!uint;
}

Json convert(PQType type)(ubyte[] val)
    if(type == PQType.Json)
{
    return parseJsonString(cast(string)val.idup);
}

string convert(PQType type)(ubyte[] val)
    if(type == PQType.Xml)
{
    return cast(string)val.idup;
}

string convert(PQType type)(ubyte[] val)
    if(type == PQType.NodeTree)
{
    assert(val.length > 0);
    return cast(string)val.idup;
}

float convert(PQType type)(ubyte[] val)
    if(type == PQType.Float4)
{
    assert(val.length == 4);
    return val.read!float;
}

float convert(PQType type)(ubyte[] val)
    if(type == PQType.Float8)
{
    assert(val.length == 8);
    return val.read!double;
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
    return val.read!long;
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
         if(type == PQType.Bool)
     {
         logger.logInfo("Testing Bool...");
         testValue!bool(logger, pool, true, "boolean");
         testValue!bool(logger, pool, false, "boolean");
     }

    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.ByteArray)
    {
        ubyte[] genRand(size_t n)
        {
            auto builder = appender!(ubyte[]);
            foreach(i; 0..n)
                builder.put(cast(ubyte)uniform(0u, 255u));
            return builder.data; 
        }
        
        logger.logInfo("Testing ByteArray...");
        foreach(i; 0..100)
            testValue!(ubyte[], escapeBytea)(logger, pool, genRand(i), "bytea");

    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Char)
    {
        logger.logInfo("Testing Char...");
        alias testValue!(string, to!string, (str) {
                str = str.strip('\'');
                return str == `\` ? `\0` : str;}) test;
        
        test(logger, pool, `'\0'`, `"char"`);
        test(logger, pool, `''''`, `"char"`);
        foreach(char c; char.min .. char.max)
            if((['\0', '\'']).find(c).empty && isValid(`'`~c~`'`))
                test(logger, pool, `'`~c~`'`, `"char"`);
        
    }
    
    string genRandString(size_t n)
    {
        auto builder = appender!string;
        immutable aphs = "1234567890qwertyuiopasdfghjklzxcvbnm";
        foreach(i; 0..n)
            builder.put(aphs[uniform(0, aphs.length)]);
        return builder.data;    
    }
        
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Name)
    {
        logger.logInfo("Testing Name...");
        
        foreach(i; 0..100)
            testValue!(string, to!string, (str) => str.strip('\''))(logger, pool, `'`~genRandString(63)~`'`, "name");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Text)
    {
        logger.logInfo("Testing Text...");
        
        testValue!(string, to!string, (str) => str.strip('\''))(logger, pool, `''`, "text");      
        foreach(i; 0..100)
            testValue!(string, to!string, (str) => str.strip('\''))(logger, pool, `'`~genRandString(50)~`'`, "text");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.VariableString)
    {
        logger.logInfo("Testing varchar[n]...");
        
        testValue!(string, to!string, (str) => str.strip('\''))(logger, pool, `''`, "varchar");      
        foreach(i; 0..100)
            testValue!(string, to!string, (str) => str.strip('\''))(logger, pool, `'`~genRandString(50)~`'`, "varchar(50)");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.FixedString)
    {
        logger.logInfo("Testing char[n]...");
          
        foreach(i; 0..100)
            testValue!(string, to!string, (str) => str.strip('\''))(logger, pool, `'`~genRandString(50)~`'`, "char(50)");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.CString)
    {
        logger.logInfo("Testing cstring...");
        
        testValue!(string, to!string, (str) => str.strip('\''))(logger, pool, `''`, "cstring");   
        foreach(i; 0..100)
            testValue!(string, to!string, (str) => str.strip('\''))(logger, pool, `'`~genRandString(50)~`'`, "cstring");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Unknown)
    {
        logger.logInfo("Testing Unknown...");
        
        testValue!(string, to!string, (str) => str.strip('\''))(logger, pool, `'Unknown'`, "unknown");   
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Int8)
    {
        logger.logInfo("Testing Int8...");
        foreach(i; 0..100)
            testValue!long(logger, pool, uniform(long.min, long.max), "Int8");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Money)
    {
        logger.logInfo("Testing Money...");
        foreach(i; 0..100)
            testValue!long(logger, pool, uniform(long.min, long.max), "Int8");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Int4)
    {
        logger.logInfo("Testing Int4...");
        foreach(i; 0..100)
            testValue!int(logger, pool, uniform(int.min, int.max), "Int4");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Int2)
    {
        logger.logInfo("Testing Int2...");
        foreach(i; 0..100)
            testValue!int(logger, pool, uniform(short.min, short.max), "Int2");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Oid)
    {
        logger.logInfo("Testing Oid...");
        foreach(i; 0..100)
            testValue!Oid(logger, pool, uniform(Oid.min, Oid.max), "Oid");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.RegProc)
    {
        logger.logInfo("Testing RegProc...");
        foreach(i; 0..100)
            testValue!RegProc(logger, pool, uniform(RegProc.min, RegProc.max), "regproc");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Tid)
    {
        logger.logInfo("Testing Tid...");
        foreach(i; 0..100)
        {
            auto testTid = PQTid(uniform(uint.min, uint.max), uniform(uint.min, uint.max));
            testValue!PQTid(logger, pool, testTid, "tid");
        }
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Xid)
    {
        logger.logInfo("Testing Xid...");
        foreach(i; 0..100)
        {
            testValue!(Xid, (v) => "'"~v.to!string~"'")(logger, pool, uniform(Xid.min, Xid.max), "xid");
        }
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Cid)
    {
        logger.logInfo("Testing Cid...");
        foreach(i; 0..100)
        {   // postgres trims large cid values
            testValue!(Cid, (v) => "'"~v.to!string~"'")(logger, pool, uniform(Cid.min/4, Cid.max/4), "cid");
        }
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Json)
    {
        logger.logInfo("Testing Json...");

        auto json = Json.emptyObject;
        json.str = genRandString(10);
        json.arr = serializeToJson([4,8,15,16,23,42]);
        json.boolean = uniform(0,1) != 0;
        //json.floating = cast(double)42.0; hard to compare properly
        json.integer  = cast(long)42;
        json.nullable = null;
        json.mapping = ["1":Json(4), "2":Json(8), "3":Json(15)];
        
        testValue!(Json, (v) => "'"~v.to!string~"'")(logger, pool, json, "json");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Xml)
    {
        logger.logInfo("Testing Xml...");
        
        testValue!(string, to!string, (str) => str.strip('\''))(logger, pool, `'‹?xml version= "1.0"›'`, "xml");   
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.NodeTree)
    {
        logger.logInfo("Testing NodeTree...");
        logger.logInfo("Not testable");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Float4)
    {
        logger.logInfo("Testing Float4...");
        string convFloat(float t)
        {
           if(t == float.infinity) return "'Infinity'";
           else if(t == -float.infinity) return "'-Infinity'";
           else if(isnan(t)) return "'NaN'";
           else return t.to!string;
        }
        testValue!(float, convFloat)(logger, pool, float.infinity, "Float4");
        testValue!(float, convFloat)(logger, pool, -float.infinity, "Float4");
        testValue!(float, convFloat)(logger, pool, -float.nan, "Float4");
        
        foreach(i; 0..100)
            testValue!(float, convFloat)(logger, pool, uniform(-100.0, 100.0), "Float4");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Float8)
    {
        logger.logInfo("Testing Float8...");
        string convFloat(double t)
        {
           if(t == double.infinity) return "'Infinity'";
           else if(t == -double.infinity) return "'-Infinity'";
           else if(isnan(t)) return "'NaN'";
           else return t.to!string;
        }
        testValue!(double, convFloat)(logger, pool, double.infinity, "Float8");
        testValue!(double, convFloat)(logger, pool, -double.infinity, "Float8");
        testValue!(double, convFloat)(logger, pool, -double.nan, "Float8");
        
        foreach(i; 0..100)
            testValue!(double, convFloat)(logger, pool, uniform(-100.0, 100.0), "Float8");
    }
}