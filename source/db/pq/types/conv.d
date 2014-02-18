// Written in D programming language
/**
*   Utilities for conversion from PostgreSQL binary format.
*
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module db.pq.types.conv;

import db.pq.types.oids;
import vibe.data.bson;
import std.traits;
import util;

import db.pq.types.geometric;
import db.pq.types.inet;
import db.pq.types.numeric;
import db.pq.types.plain;
import db.pq.types.time;

bool nonConvertable(PQType type)
{
    switch(type)
    {
        case PQType.TypeCatalog: return true;
        case PQType.AttributeCatalog: return true;
        case PQType.ProcCatalog: return true;
        case PQType.ClassCatalog: return true; 
        case PQType.StorageManager: return true;
        case PQType.Line: return true;
        
        // awaiting implementation
        case PQType.Int2Array: return true;
        case PQType.Int4Array: return true;
        case PQType.TextArray: return true;
        case PQType.OidArray: return true;
        case PQType.Float4Array: return true;
        case PQType.AccessControlList: return true;
        case PQType.CStringArray: return true;
        
        case PQType.FixedString: return true;
        case PQType.VariableString: return true;
        
        case PQType.Date: return true;
        case PQType.Time: return true;
        //case PQType.TimeStamp: return true;
        //case PQType.TimeStampWithZone: return true;
        case PQType.TimeInterval: return true;
        case PQType.TimeWithZone: return true;
        
        case PQType.FixedBitString: return true;
        case PQType.VariableBitString: return true;
        
        //case PQType.Numeric: return true;
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

Bson toBson(PQType type)(ubyte[] val)
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
    
    auto convVal = convert!type(val);
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

Bson pqToBson(PQType type, ubyte[] val)
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
                return toBson!t(val);
            }
        }
    }
    assert(false, "Unknown type "~to!string(type)~"!");
}

version(IntegrationTest2)
{
    import db.pool;
    import log;
    
    void testConvertions(shared ILogger logger, IConnectionPool pool)
    {
        test!(PQType.Numeric)(logger, pool);
        test!(PQType.Bool)(logger, pool);
        test!(PQType.ByteArray)(logger, pool);
        test!(PQType.Char)(logger, pool);
        test!(PQType.Name)(logger, pool);
        test!(PQType.Int8)(logger, pool);
        test!(PQType.Int4)(logger, pool);
        test!(PQType.Int2)(logger, pool);
    }
}