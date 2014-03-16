// Written in D programming language
/**
*   Utilities for conversion from PostgreSQL binary format.
*
*   Copyright: © 2014 DSoftOut
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module db.pq.types.conv;

import db.pq.types.oids;
import db.connection;
import vibe.data.bson;
import std.conv;
import std.traits;
import std.typetuple;
import util;

import db.pq.types.geometric;
import db.pq.types.inet;
import db.pq.types.numeric;
import db.pq.types.plain;
import db.pq.types.time;
import db.pq.types.array;

bool nonConvertable(PQType type)
{
    switch(type)
    {
        case PQType.RegProc: return true;
        case PQType.TypeCatalog: return true;
        case PQType.AttributeCatalog: return true;
        case PQType.ProcCatalog: return true;
        case PQType.ClassCatalog: return true; 
        case PQType.StorageManager: return true;
        case PQType.Tid: return true;
        case PQType.Line: return true;
        case PQType.AccessControlList: return true;
        
        // awaiting implementation
        case PQType.FixedBitString: return true;
        case PQType.VariableBitString: return true;
        
        case PQType.RefCursor: return true;
        case PQType.RegProcWithArgs: return true;
        case PQType.RegOperator: return true;
        case PQType.RegOperatorWithArgs: return true;
        case PQType.RegClass: return true;
        case PQType.RegType: return true;
        case PQType.RegTypeArray: return true;
        
        case PQType.UUID: return true;
        case PQType.TSVector: return true;
        case PQType.GTSVector: return true;
        case PQType.TSQuery: return true;
        case PQType.RegConfig: return true;
        case PQType.RegDictionary: return true;
        
        case PQType.Int4Range: return true;
        case PQType.NumRange: return true;
        case PQType.TimeStampRange: return true;
        case PQType.TimeStampWithZoneRange: return true;
        case PQType.DateRange: return true;
        case PQType.Int8Range: return true;
        
        // Pseudo types
        case PQType.Record: return true;
        case PQType.RecordArray: return true;
        case PQType.CString: return true;
        case PQType.AnyVoid: return true;
        case PQType.AnyArray: return true;
        case PQType.Void: return true;
        case PQType.Trigger: return true;
        case PQType.EventTrigger: return true;
        case PQType.LanguageHandler: return true;
        case PQType.Internal: return true;
        case PQType.Opaque: return true;
        case PQType.AnyElement: return true;
        case PQType.AnyNoArray: return true;
        case PQType.AnyEnum: return true;
        case PQType.FDWHandler: return true;
        case PQType.AnyRange: return true;
        default: return false;
    }
}

Bson toBson(PQType type)(ubyte[] val, shared IConnection conn)
{
    template IsNativeSupport(T)
    {  
        import std.range;
        
        static if (is(T == string) || is(T == ubyte[]) || is(T == Json))
        {
            enum IsNativeSupport = true;
        }
        else static if(isArray!T)
        {
            enum IsNativeSupport = IsNativeSupport!(ElementType!T);
        }
        else
        {
            enum IsNativeSupport = 
                   is(T == bool)
                || is(T == float)
                || is(T == double)
                || is(T == short)
                || is(T == ushort)
                || is(T == int)
                || is(T == uint)
                || is(T == long)
                || is(T == ulong);
        }
    }
    
    // Checking if the convert function needs connection for reverse link
    static if(is(ParameterTypeTuple!(convert!type) == TypeTuple!(ubyte[])))
    {
        auto convVal = convert!type(val);
    } else static if(is(ParameterTypeTuple!(convert!type) == TypeTuple!(ubyte[], shared IConnection)))
    {
        auto convVal = convert!type(val, conn);
    } else
    {
        static assert(false, text("Doesn't support '",ParameterTypeTuple!(convert!type),"' signature of converting function"));
    }
    alias typeof(convVal) T;
    
    static if(is(T == ubyte[]))
    {
        return serializeToBson(new BsonBinData(BsonBinData.Type.generic, convVal.idup));
    }
    else static if(IsNativeSupport!T)
    {
        return serializeToBson(convVal); 
    } 
    else static if(is(T == SysTime))
    {
        return serializeToBson(convVal.stdTime);
    } 
    else static if(is(T == Numeric))
    {
        double store;
        if(convVal.canBeNative(store))
            return serializeToBson(store);
        else
            return serializeToBson(convVal.to!string);
    }
    else static if(is(T == struct))
    {
        return serializeToBson(convVal);
    }
    else
    {
        return serializeToBson(convVal.to!string);   
    }
}

Bson pqToBson(PQType type, ubyte[] val, shared IConnection conn)
{
    foreach(ts; __traits(allMembers, PQType))
    {
        enum t = mixin("PQType."~ts);
        if(type == t)
        {
            static if(nonConvertable(t))
            {
                enum errMsg = ts ~ " is not supported!";
                pragma(msg, errMsg);
                assert(false,errMsg);
            } else
            {
                return toBson!t(val, conn); 
            }
        }
    }
    assert(false, "Unknown type "~to!string(type)~"!");
}

version(IntegrationTest2)
{
    import db.pool;
    import log;
    
    void testConvertions(shared ILogger logger, shared IConnectionPool pool)
    {
        foreach(t; __traits(allMembers, PQType))
        {
            enum type = mixin("PQType."~t);
            static if(!nonConvertable(type)) 
            {
                test!type(logger, pool);
            }
        }
    }
}