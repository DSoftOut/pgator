// Written in D programming language
/**
*   PostgreSQL typed arrays binary data format.
*
*   Copyright: © 2014 DSoftOut
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module db.pq.types.array;

import db.pq.types.oids;
import db.connection;
import derelict.pq.pq;
import std.array;
import std.bitmanip;
import std.conv;
import std.traits;

import std.datetime;
import db.pq.types.all;

private struct Vector(T)
{
    int     ndim;
    int     dataoffset;
    Oid     elemtype;
    int     dim1;
    int     lbound1;
    T[]     values;
}

private Vector!T readVec(T, PQType type)(ubyte[] arr, shared IConnection conn)
{
    if(arr.length == 0) return Vector!T();
    std.stdio.writeln(arr);
    
    assert(arr.length >= 2*int.sizeof + Oid.sizeof, text(
            "Expected min array size ", 2*int.sizeof + Oid.sizeof, ", but got ", arr.length));
    Vector!T vec;
    
    vec.ndim    = arr.read!int;
    vec.dataoffset = arr.read!int;
    vec.elemtype   = arr.read!Oid;
    if(arr.length == 0) return vec;
    vec.dim1       = arr.read!int;
    vec.lbound1    = arr.read!int;
    
    auto builder = appender!(T[]);
    while(arr.length > 0)
    {
        auto maybeLength  = arr.read!uint;
        // if got [255, 255, 255, 255] - there is special case for NULL in array
        if(maybeLength == uint.max)
        {
            static if(is(T == class) || is(T == interface))
            {
               builder.put(null);
            } 
            else
            {
                builder.put(T.init);
            }
            continue;
        }
        
        // can cast to array size
        auto length = cast(size_t)maybeLength; 
        
        static if(__traits(compiles, db.pq.types.all.convert!type(arr)))
        {
            auto value = db.pq.types.all.convert!type(arr[0..length]); 
            builder.put(value);
            arr = arr[length..$];
        } else static if(__traits(compiles, db.pq.types.all.convert!type(arr, conn)))
        { 
            auto value = db.pq.types.all.convert!type(arr[0..length], conn); 
            builder.put(value); 
            arr = arr[length..$];
        } else
        {
            static assert(false, "There is no convert function for libpq type: "~type.to!text);
        }
    }
    vec.values = builder.data;
    return vec;    
}

mixin ArraySupport!(
    PQType.Int2Vector,              short[],                PQType.Int2,
    PQType.Int2Array,               short[],                PQType.Int2,
    PQType.Int4Array,               int[],                  PQType.Int4,
    PQType.OidVector,               Oid[],                  PQType.Oid,
    PQType.OidArray,                Oid[],                  PQType.Oid,
    PQType.TextArray,               string[],               PQType.Text,
    PQType.CStringArray,            string[],               PQType.Text,
    PQType.Float4Array,             float[],                PQType.Float4,
    PQType.BoolArray,               bool[],                 PQType.Bool,
    PQType.ByteArrayArray,          ubyte[][],              PQType.ByteArray,
    PQType.CharArray,               char[],                 PQType.Char,
    PQType.NameArray,               string[],               PQType.Name,
    PQType.Int2VectorArray,         short[][],              PQType.Int2VectorArray,
    PQType.XidArray,                Xid[],                  PQType.Xid,
    PQType.CidArray,                Cid[],                  PQType.Cid,
    PQType.OidVectorArray,          Oid[][],                PQType.OidVector,
    PQType.FixedStringArray,        string[],               PQType.FixedString,
    PQType.VariableStringArray,     string[],               PQType.VariableString,
    PQType.Int8Array,               long[],                 PQType.Int8,
    PQType.PointArray,              Point[],                PQType.Point,
    PQType.LineSegmentArray,        LineSegment[],          PQType.LineSegment,
    PQType.PathArray,               Path[],                 PQType.Path,
    PQType.BoxArray,                Box[],                  PQType.Box,
    PQType.Float8Array,             double[],               PQType.Float8,
    PQType.AbsTimeArray,            PGAbsTime[],            PQType.AbsTime,
    PQType.RelTimeArray,            PGRelTime[],            PQType.RelTime,
    PQType.IntervalArray,           PGInterval[],           PQType.Interval,
    PQType.PolygonArray,            Polygon[],              PQType.Polygon,
    PQType.MacAddressArray,         PQMacAddress[],         PQType.MacAddress,
    PQType.HostAdressArray,         PQInetAddress[],        PQType.HostAddress,
    PQType.NetworkAdressArray,      PQInetAddress[],        PQType.NetworkAddress,
    PQType.TimeStampArray,          PGTimeStamp[],          PQType.TimeStamp,
    PQType.DateArray,               Date[],                 PQType.Date,
    PQType.TimeArray,               PGTime[],               PQType.Time,
    PQType.TimeStampWithZoneArray,  PGTimeStampWithZone[],  PQType.TimeStampWithZone,
    PQType.TimeIntervalArray,       TimeInterval[],         PQType.TimeInterval,
    PQType.NumericArray,            Numeric[],              PQType.Numeric,
    PQType.TimeWithZoneArray,       PGTimeWithZone[],       PQType.TimeWithZone,
    );

/**
*   Template magic lives here! Generates templates and functions to work with
*   templates. Expects input argument as triples of PQType value, corresponding
*   D type and corresponding element type of libpq type.
*/    
private mixin template ArraySupport(PairsRaw...)
{
    import std.range;
    import std.traits;
    
    /// To work with D tuples
    private template Tuple(E...)
    {
        alias Tuple = E;
    }
    
    /// Custom tuple for a pair
    private template ArrayTuple(TS...)
    {
        static assert(TS.length == 3);
        enum id = TS[0];
        alias TS[1] type;
        enum elementType = TS[2];
    } 
    
    /// Converts unstructured pairs in ArrayTuple tuple
    private template ConvertPairs(TS...)
    {
        static assert(TS.length % 3 == 0, "ArraySupport expected even count of arguments!");
        static if(TS.length == 3)
        {
            alias Tuple!(ArrayTuple!(TS[0], TS[1], TS[2])) ConvertPairs;
        } else
        {
            static assert(is(typeof(TS[0]) == PQType), "ArraySupport expected PQType value as first triple argument!");
            static assert(is(TS[1]), "ArraySupport expected a type as second triple argument!"); 
            static assert(is(typeof(TS[0]) == PQType), "ArraySupport expected PQType value as third triple argument!");
            
            alias Tuple!(ArrayTuple!(TS[0], TS[1], TS[2]), ConvertPairs!(TS[3..$])) ConvertPairs;
        }
    }
    
    /// Structured pairs
    alias ConvertPairs!PairsRaw Pairs;
    
    /// Checks if PQType value is actually array type
    template IsArrayType(TS...)
    {
        private template genCompareExpr(US...)
        {
            static if(US.length == 0)
            {
                enum genCompareExpr = "";
            } else static if(US.length == 1)
            {
                enum genCompareExpr = "T == PQType."~US[0].id.to!string;
            } else
            {
                enum genCompareExpr = "T == PQType."~US[0].id.to!string~" || "
                    ~ genCompareExpr!(US[1..$]);
            }
        }
        
        static assert(TS.length > 0, "IsArrayType expected argument count > 0!");
        alias TS[0] T;
        enum IsArrayType = mixin(genCompareExpr!(Pairs));
    }
    
    /// Returns oid of provided element type or generates error if it is not a libpq array
    template ArrayElementType(TS...)
    {
        static assert(TS.length > 0, "ArrayElementType expected argument!");
        
        private enum T = TS[0];
        
        static assert(is(typeof(TS[0]) == PQType), "ArrayElementType expected PQType value as argument!");
        static assert(IsArrayType!(TS[0]), TS[0].to!string~" is not a libpq array!");
        
        template FindArrayTuple(TS...)
        {
            static if(TS.length == 0)
            {
                static assert("Cannot find "~T.to!string~" in array types!");
            } else
            {
                static if(TS[0] == T)
                {
                    enum FindArrayTuple = TS[3];
                } else
                {
                    enum FindArrayTuple = FindArrayTuple!(TS[1..$]);
                }
            }
        }
        
        enum ArrayElementType = FindArrayTuple!TS;
    }
    
    /// Generates set of converting functions from ubyte[] to types in triples
    private template genConvertFunctions(TS...)
    {
        private template genConvertFunction(TS...)
        {
            alias TS[0] T;
            
            enum genConvertFunction = T.type.stringof ~ " convert(PQType type)(ubyte[] val, shared IConnection conn)\n"
                "\t if(type == PQType."~T.id.to!string~")\n{\n"
                "\t return val.readVec!("~ForeachType!(T.type).stringof~", PQType."~T.elementType.to!string~")(conn).values;\n}";
        }
           
        static if(TS.length == 0)
        {
            enum genConvertFunctions = "";
        } else
        {
            enum genConvertFunctions = genConvertFunction!(TS[0]) ~"\n"~genConvertFunctions!(TS[1..$]);
        }
    }

    mixin(genConvertFunctions!Pairs);
}   

version(IntegrationTest2)
{
    import db.pq.types.test;
    import db.pq.types.plain;
    import db.pool;
    import std.array;
    import std.random;
    import std.math;
    import std.traits;
    import dlogg.log;

    string convertArray(T, bool wrapQuotes = true)(T[] ts)
    {
        auto builder = appender!string;
        foreach(i,t; ts)
        {
            enum needQuotes = (isSomeString!T || isSomeChar!T || is(T == Xid) || is(T == Cid)) && wrapQuotes;
            static if(needQuotes) builder.put("'");
            static if(isFloatingPoint!T)
            {
               if(t == T.infinity) builder.put("'Infinity'");
               else if(t == -T.infinity) builder.put("'-Infinity'");
               else if(isnan(t)) builder.put("'NaN'");
               else builder.put(t.to!string);
            } else
            {
                builder.put(t.to!string);
            }
            static if(needQuotes) builder.put("'");
            if(i != ts.length-1)
                builder.put(", ");
        }
        return "ARRAY["~builder.data~"]";
    } 
    
    struct Name {};
    
    U[] randArray(T, U=T)(size_t n)
    {
        auto builder = appender!(U[]);
        foreach(i; 0..n)
        {
            static if(isSomeChar!T)
            {
                immutable alph = "1234567890asdfghjkklzxcvbnm,.?!@#$%^&*()+-|";
                builder.put(alph[uniform(0,alph.length)]);
            }
            else static if(is(T == string))
            {
                immutable alph = "1234567890asdfghjkklzxcvbnm,.?!@#$%^&*()+-|";
                auto zbuilder = appender!string;
                foreach(j; 0..n)
                    zbuilder.put(alph[uniform(0,alph.length)]);
                builder.put(zbuilder.data);
            }  
            else static if(is(T == Name))
            {
                immutable alph = "1234567890asdfghjkklzxcvbnm,.?!@#$%^&*()+-|";
                auto zbuilder = appender!string;
                foreach(j; 0..63)
                    zbuilder.put(alph[uniform(0,alph.length)]);
                builder.put(zbuilder.data);
            }
            else static if(is(T == float))
            {
                builder.put(uniform(-1000.0, 1000.0));
            } 
            else static if(is(T == bool))
            {
                builder.put(uniform!"[]"(0,1) != 0);
            }
            else static if(isArray!T)
            {
                builder.put(randArray!(ElementType!T)(n));
            }
            else static if(is(T == Cid))
            {
                builder.put(uniform(Cid.min/4, Cid.max/4));
            }
            else static if(isFloatingPoint!T)
            {
                builder.put(uniform(-T.max, T.max));
            }
            else
            {
                builder.put(uniform(T.min, T.max));
            }
        }
        return builder.data;    
    }
    
    void testArray(T, alias typeTrans = (n, name) => name)(shared ILogger logger, shared IConnectionPool pool, string tname, size_t bn = 0, size_t en = 100)
    {
        logger.logInfo("Testing "~tname~"...");
        foreach(i; bn..en)
        {
            static if(is(T == ubyte[]))
            {
                testValue!(T[], (a) => a.map!(a => escapeBytea(a)).array.convertArray!(string, false), id)(logger, pool, randArray!T(i), typeTrans(i, tname));
            } else static if(isSomeChar!T)
            {
                testValue!(string[], convertArray)(logger, pool, randArray!T(i).map!(a => [cast(char)a].idup).array, typeTrans(i, tname));
            } else static if(is(T == Name))
            {
                testValue!(string[], convertArray)(logger, pool, randArray!(T, string)(i), typeTrans(i, tname));
            } else static if(isArray!T && !isSomeString!T)
            {
                testValue!(T[], (a) 
                    {
                        auto builder = appender!(string[]);
                        foreach(b; a)
                        {
                            builder.put(b.convertArray);
                        }
                        return builder.data.convertArray!(string, false);
                    }
                    )(logger, pool, randArray!T(i), typeTrans(i, tname));
            }
            else
            {
                testValue!(T[], convertArray)(logger, pool, randArray!T(i), typeTrans(i, tname));
            }
        }
    }
        
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Int2Vector)
    { 
        testArray!short(logger, pool, "int2vector");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.OidVector)
    {       
        testArray!Oid(logger, pool, "oidvector");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.OidArray)
    {       
        testArray!Oid(logger, pool, "oid[]");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Int2Array)
    {
        testArray!short(logger, pool, "int2[]");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Int4Array)
    {
        testArray!int(logger, pool, "int4[]");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.TextArray)
    {
        testArray!string(logger, pool, "text[]");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.CStringArray)
    {
        testArray!string(logger, pool, "cstring[]");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.BoolArray)
    {
        testArray!bool(logger, pool, "bool[]");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.ByteArrayArray)
    {
        testArray!(ubyte[])(logger, pool, "bytea[]");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.CharArray)
    {
        testArray!char(logger, pool, "char[]");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.NameArray)
    {
        testArray!Name(logger, pool, "name[]");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Int2VectorArray)
    {
        logger.logInfo("Not testable");
        //testArray!(short[])(logger, pool, "int2vector[]");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.XidArray)
    {
        testArray!Xid(logger, pool, "xid[]");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.CidArray)
    {
        testArray!Cid(logger, pool, "cid[]");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.OidVectorArray)
    {
        logger.logInfo("Not testable");
        //testArray!(Oid[])(logger, pool, "oidvector[]");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.FixedStringArray)
    {
        testArray!(string, (n, name) => text("char(",n,")[]"))(logger, pool, "char(n)[]", 1, 100);
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.VariableStringArray)
    {
        testArray!(string, (n, name) => text("varchar(",n,")[]"))(logger, pool, "varchar(n)[]", 1, 100);
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Int8Array)
    {
        testArray!long(logger, pool, "int8[]");
    }
        
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.PointArray)
    {
        //testArray!string(logger, pool, "point[]");
    }

    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.LineSegmentArray)
    {
        //testArray!string(logger, pool, "lseg[]");
    }

    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.PathArray)
    {
        //testArray!string(logger, pool, "path[]");
    }

    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.BoxArray)
    {
        //testArray!string(logger, pool, "box[]");
    }

    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Float8Array)
    {
        testArray!double(logger, pool, "float8[]");
    }

    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.AbsTimeArray)
    {
        //testArray!string(logger, pool, "abstime[]");
    }

    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.RelTimeArray)
    {
        //testArray!string(logger, pool, "reltime[]");
    }

    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.IntervalArray)
    {
        //testArray!string(logger, pool, "interval[]");
    }

    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.PolygonArray)
    {
        //testArray!string(logger, pool, "polygon[]");
    }

    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.MacAddressArray)
    {
        //testArray!string(logger, pool, "macaddress[]");
    }

    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.HostAdressArray)
    {
        //testArray!string(logger, pool, "inet[]");
    }

    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.NetworkAdressArray)
    {
        //testArray!string(logger, pool, "cidr[]");
    }

    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.TimeStampArray)
    {
        //testArray!string(logger, pool, "timestamp[]");
    }

    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.DateArray)
    {
        //testArray!string(logger, pool, "date[]");
    }

    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.TimeArray)
    {
        //testArray!string(logger, pool, "time[]");
    }

    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.TimeStampWithZoneArray)
    {
        //testArray!string(logger, pool, "timestamp with zone[]");
    }

    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.TimeIntervalArray)
    {
        //testArray!string(logger, pool, "TimeInterval[]");
    }

    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.NumericArray)
    {
        //testArray!string(logger, pool, "numeric[]");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.TimeWithZoneArray)
    {
        //testArray!string(logger, pool, "time with zone[]");
    }


    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Float4Array)
    {
        testArray!float(logger, pool, "float4[]"); 
        testValue!(float[], convertArray)(logger, pool, [float.infinity], "float4[]");
        testValue!(float[], convertArray)(logger, pool, [-float.infinity], "float4[]");
        testValue!(float[], convertArray)(logger, pool, [float.nan], "float4[]");
    }
}
