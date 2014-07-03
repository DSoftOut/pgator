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
import dlogg.log;
import std.conv;
import std.traits;
import std.typetuple;
import util;

import db.pq.types.all;

bool nonConvertable(PQType type)
{
    switch(type)
    {
        case PQType.RegProc: return true;
        case PQType.RegProcArray: return true;
        case PQType.TypeCatalog: return true;
        case PQType.AttributeCatalog: return true;
        case PQType.ProcCatalog: return true;
        case PQType.ClassCatalog: return true; 
        case PQType.StorageManager: return true;
        case PQType.Tid: return true;
        case PQType.TidArray: return true;
        case PQType.Line: return true;
        case PQType.AccessControlList: return true;
        case PQType.AccessControlListArray: return true;
        
        // awaiting implementation
        case PQType.FixedBitString: return true;
        case PQType.FixedBitStringArray: return true;
        case PQType.VariableBitString: return true;
        case PQType.VariableBitStringArray: return true;
        
        case PQType.RefCursor: return true;
        case PQType.RefCursorArray: return true;
        case PQType.RegProcWithArgs: return true;
        case PQType.RegProcWithArgsArray: return true;
        case PQType.RegOperator: return true;
        case PQType.RegOperatorArray: return true;
        case PQType.RegOperatorWithArgs: return true;
        case PQType.RegOperatorWithArgsArray: return true;
        case PQType.RegClass: return true;
        case PQType.RegClassArray: return true;
        case PQType.RegType: return true;
        case PQType.RegTypeArray: return true;
        
        case PQType.UUID: return true;
        case PQType.UUIDArray: return true;
        case PQType.TSVector: return true;
        case PQType.TSVectorArray: return true;
        case PQType.GTSVector: return true;
        case PQType.GTSVectorArray: return true;
        case PQType.TSQuery: return true;
        case PQType.TSQueryArray: return true;
        case PQType.RegConfig: return true;
        case PQType.RegConfigArray: return true;
        case PQType.RegDictionary: return true;
        case PQType.RegDictionaryArray: return true;
        case PQType.TXidSnapshot: return true;
        case PQType.TXidSnapshotArray: return true;
        
        case PQType.Int4Range: return true;
        case PQType.Int4RangeArray: return true;
        case PQType.NumRange: return true;
        case PQType.NumRangeArray: return true;
        case PQType.TimeStampRange: return true;
        case PQType.TimeStampRangeArray: return true;
        case PQType.TimeStampWithZoneRange: return true;
        case PQType.TimeStampWithZoneRangeArray: return true;
        case PQType.DateRange: return true;
        case PQType.DateRangeArray: return true;
        case PQType.Int8Range: return true;
        case PQType.Int8RangeArray: return true;
        
        // Pseudo types
        case PQType.CString: return true;
        case PQType.Record: return true;
        case PQType.RecordArray: return true;
        case PQType.AnyVoid: return true;
        case PQType.AnyArray: return true;
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
    
    bool checkNullValues(T)(out Bson bson)
    {
        static if(is(T == string))
        {
            if(val.length == 0)
            {
                bson = Bson("");
                return true;
            }
        }
        else static if(isArray!T)
        {
            if(val.length == 0) 
            {
                bson = serializeToBson(cast(T[])[]);
                return true;
            }
        } else
        {
            if(val.length == 0)
            {
                bson = Bson(null);
                return true;
            }
        }
        return false;
    }
    
    // Checking if the convert function needs connection for reverse link
    static if(is(ParameterTypeTuple!(convert!type) == TypeTuple!(ubyte[])))
    {
        alias typeof(convert!type(val)) T;
        
        Bson retBson; if(checkNullValues!T(retBson)) return retBson;
    
        auto convVal = convert!type(val);
    } else static if(is(ParameterTypeTuple!(convert!type) == TypeTuple!(ubyte[], shared IConnection)))
    {
        alias typeof(convert!type(val, conn)) T;
    
        Bson retBson; if(checkNullValues!T(retBson)) return retBson;
        
        auto convVal = convert!type(val, conn);
    } else
    {
        static assert(false, text("Doesn't support '",ParameterTypeTuple!(convert!type),"' signature of converting function"));
    }
    
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
    else static if(is(T == PGNumeric))
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

Bson pqToBson(PQType type, ubyte[] val, shared IConnection conn, shared ILogger logger)
{
    try
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
    }
    catch(Exception e)
    {
        logger.logError(text("Binary protocol exception: ", e.msg));
        logger.logError(text("Converting from: ", type));
        logger.logError(text("Payload: ", val));
        logger.logError(text("Stack trace: ", e));
        throw e;
    }
    catch(Error err)
    {
        logger.logError(text("Binary protocol error (logic error): ", err.msg));
        logger.logError(text("Converting from: ", type));
        logger.logError(text("Payload: ", val));
        logger.logError(text("Stack trace: ", err));
        throw err;
    }
    
    debug assert(false, "Unknown type "~to!string(type)~"!");
    else
    {
        throw new Exception(text("pgator doesn't support typeid ", type," at the moment! Please, visit "
                "https://github.com/DSoftOut/pgator and open an issue."));
    }
}

version(IntegrationTest2)
{
    import db.pool;
    import dlogg.log;
    
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
