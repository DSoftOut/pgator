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
import derelict.pq.pq;
import std.array;
import std.bitmanip;
import std.conv;

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

private Vector!T readVec(T, PQType type)(ubyte[] arr)
{
    if(arr.length == 0) return Vector!T();
    
    assert(arr.length >= 2*int.sizeof + Oid.sizeof, text(
            "Expected min array size ", 2*int.sizeof + Oid.sizeof, ", but got ", arr.length));
    Vector!T vec;
    
    vec.ndim    = arr.read!int;
    vec.dataoffset = arr.read!int;
    vec.elemtype   = arr.read!Oid;
    if(arr.length == 0) return vec;
    vec.dim1       = arr.read!int;
    vec.lbound1    = arr.read!int;
    
    static if(!is(T == string)) assert(arr.length % T.sizeof == 0);
    auto builder = appender!(T[]);
    while(arr.length > 0)
    {
        auto length = cast(size_t)arr.read!int;

        auto value = db.pq.types.all.convert!type(arr[0..length]);
        builder.put(value);
        arr = arr[length..$];
    }
    vec.values = builder.data;
    return vec;    
}

mixin ArraySupport!(
    PQType.Int2Vector,   short[],   PQType.Int2,
    PQType.Int2Array,    short[],   PQType.Int2,
    PQType.Int4Array,    int[],     PQType.Int4,
    PQType.OidVector,    Oid[],     PQType.Oid,
    PQType.OidArray,     Oid[],     PQType.Oid,
    PQType.TextArray,    string[],  PQType.Text,
    PQType.CStringArray, string[],  PQType.Text,
    PQType.Float4Array,  float[],   PQType.Float4,
    );

/**
*   Template magic lives here! Generates templates and functions to work with
*   templates. Expects input argument as triples of PQType value, corresponding
*   D type and corresponding element type of libpq type.
*/    
private mixin template ArraySupport(PairsRaw...)
{
    import std.range;
    
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
            
            enum genConvertFunction = T.type.stringof ~ " convert(PQType type)(ubyte[] val)\n"
                "\t if(type == PQType."~T.id.to!string~")\n{\n"
                "\t return val.readVec!("~ElementType!(T.type).stringof~", PQType."~T.elementType.to!string~").values;\n}";
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
    import db.pool;
    import std.array;
    import std.random;
    import std.math;
    import log;
    
    string convertArray(T)(T[] ts)
    {
        auto builder = appender!string;
        foreach(i,t; ts)
        {
            static if(is(T == string)) builder.put("'");
            static if(is(T == float))
            {
               if(t == T.infinity) builder.put("'Infinity'");
               else if(t == -T.infinity) builder.put("'-Infinity'");
               else if(isnan(t)) builder.put("'NaN'");
               else builder.put(t.to!string);
            } else
            {
                builder.put(t.to!string);
            }
            static if(is(T == string)) builder.put("'");
            if(i != ts.length-1)
                builder.put(", ");
        }
        return "ARRAY["~builder.data~"]";
    } 
    
    T[] randArray(T)(size_t n)
    {
        auto builder = appender!(T[]);
        foreach(i; 0..n)
        {
            static if(is(T == string))
            {
                immutable alph = "1234567890asdfghjkklzxcvbnm,.?!@#$%^&*()+-|";
                auto zbuilder = appender!string;
                foreach(j; 0..uniform(0,100))
                    zbuilder.put(alph[uniform(0,alph.length)]);
                builder.put(zbuilder.data);
            } else static if(is(T == float))
            {
                builder.put(uniform(-1000.0, 1000.0));
            }
            else
            {
                builder.put(uniform(T.min, T.max));
            }
        }
        return builder.data;    
    }
    
    void testArray(T)(shared ILogger logger, shared IConnectionPool pool, string tname)
    {
        logger.logInfo("Testing "~tname~"...");
        foreach(i; 0..100)
            testValue!(T[], convertArray)(logger, pool, randArray!T(i), tname);
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
        if(type == PQType.Float4Array)
    {
        testArray!float(logger, pool, "float4[]"); 
        testValue!(float[], convertArray)(logger, pool, [float.infinity], "float4[]");
        testValue!(float[], convertArray)(logger, pool, [-float.infinity], "float4[]");
        testValue!(float[], convertArray)(logger, pool, [float.nan], "float4[]");
    }
}