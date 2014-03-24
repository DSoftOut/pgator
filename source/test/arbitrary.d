// Written in D programming language
/**
*   Module defines routines for generating testing sets.
*   
*   To define Arbitrary template for particular type $(B T) (or types) you should follow
*   compile-time interface:
*   <ul>
*       <li>Define $(B generate) function that takes nothing and returns range of $(B T).
*           This function is used to generate random sets of testing data. Size of required
*           sample isn't passed thus use lazy ranges to generate possible infinite set of
*           data.</li>
*       <li>Define $(B shrink) function that takes value of $(B T) and returns range of
*           truncated variations. This function is used to reduce failing case data to
*           minimum possible set. You can return empty array if you like to get large bunch
*           of random data.</li>
*       <li>Define $(B specialCases) function that takes nothing and returns range of $(B T).
*           This function is used to test some special values for particular type like NaN or
*           null pointer. You can return empty array if no testing on special cases is required.</li>
*   </ul>
*
*   Usually useful practice is put static assert with $(B CheckArbitrary) template into your implementation
*   to actually get confidence that you've done it properly. 
*
*   Example:
*   ---------
*
*   ---------
*
*   Copyright: © 2014 DSoftOut
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module test.arbitrary;

import std.traits;
import std.range;
import std.random;
import std.conv;
import util;

/// Minimum size of generated arrays (and strings)
enum ArrayGenSizeMin = 1;
/// Maximum size of generated arrays (and strings)
enum ArrayGenSizeMax = 32;
 
/**
*   Checks if $(B T) has Arbitrary template with
*   $(B generate), $(B shrink) and $(B specialCases) functions.
*/
template HasArbitrary(T)
{
    template HasGenerate()
    {
        static if(__traits(compiles, Arbitrary!T.generate))
        {
            alias ParameterTypeTuple!(Arbitrary!T.generate) Params;
            alias ReturnType!(Arbitrary!T.generate) RetType;
            
            enum HasGenerate = 
                isInputRange!RetType && is(ElementType!RetType == T)
                && Params.length == 0;
        } else
        {
            enum HasGenerate = false;
        }
    }
    
    template HasShrink()
    {
        static if(__traits(compiles, Arbitrary!T.shrink ))
        {
            alias ParameterTypeTuple!(Arbitrary!T.shrink) Params;
            alias ReturnType!(Arbitrary!T.shrink) RetType;
            
            enum HasShrink = 
                isInputRange!RetType 
                && (is(ElementType!RetType == T) || isSomeChar!T && isSomeChar!(ElementType!RetType))
                && Params.length == 1
                && is(Params[0] == T);                
        } else
        {
            enum HasShrink = false;
        }
    }
    
    template HasSpecialCases()
    {
        static if(__traits(compiles, Arbitrary!T.specialCases))
        {
            alias ParameterTypeTuple!(Arbitrary!T.specialCases) Params;
            alias ReturnType!(Arbitrary!T.specialCases) RetType;
            
            enum HasSpecialCases = 
                isInputRange!RetType 
                && (is(ElementType!RetType == T) || isSomeChar!T && isSomeChar!(ElementType!RetType))
                && Params.length == 0;
        } else
        {
            enum HasSpecialCases = false;
        }
    }
    
    template isFullDefined()
    {
        enum isFullDefined = 
            __traits(compiles, Arbitrary!T) &&
            HasGenerate!() &&
            HasShrink!() &&
            HasSpecialCases!();
    }
}

/**
*   Check the $(B T) type has properly defined $(B Arbitrary) template. Prints useful user-friendly messages
*   at compile time.
*
*   Good practice is put the template in static assert while defining own instances of $(B Arbitrary) to get
*   confidence about instance correctness.
*/
template CheckArbitrary(T)
{
    static assert(__traits(compiles, Arbitrary!T), "Type "~T.stringof~" doesn't have Arbitrary template!");
    static assert(HasArbitrary!T.HasGenerate!(), "Type "~T.stringof~" doesn't have generate function in Arbitrary template!");
    static assert(HasArbitrary!T.HasShrink!(), "Type "~T.stringof~" doesn't have shrink function in Arbitrary template!");
    static assert(HasArbitrary!T.HasSpecialCases!(), "Type "~T.stringof~" doesn't have specialCases function in Arbitrary template!");
    enum CheckArbitrary = HasArbitrary!T.isFullDefined!();
}

/**
*   Arbitrary for ubyte, byte, ushort, short, uing, int, ulong, long.
*/
template Arbitrary(T)
    if(isIntegral!T)
{
    static assert(CheckArbitrary!T);
    
    auto generate()
    {
        return (() => Maybe!T(uniform!"[]"(T.min, T.max))).generator;
    }
    
    auto shrink(T val)
    {
        class Shrinker
        {
            T saved;
            
            this(T firstVal)
            {
                saved = firstVal;
            }
            
            Maybe!T shrink()
            {
                if(saved == 0) return Maybe!T.nothing;
                
                if(saved > 0) saved--;
                if(saved < 0) saved++;
                
                return Maybe!T(saved);
            }
        }
        
        return (&(new Shrinker(val)).shrink).generator;
    }
    
    T[] specialCases()
    {
        return [T.min, 0, T.max];
    }
}
unittest
{
    Arbitrary!ubyte.generate;
    Arbitrary!ubyte.specialCases;
    assert(Arbitrary!ubyte.shrink(10).take(10).equal([9,8,7,6,5,4,3,2,1,0]));
    
    Arbitrary!byte.generate;
    Arbitrary!byte.specialCases;
    assert(Arbitrary!byte.shrink(10).take(10).equal([9,8,7,6,5,4,3,2,1,0]));
    assert(Arbitrary!byte.shrink(-10).take(10).equal([-9,-8,-7,-6,-5,-4,-3,-2,-1,0]));
    
    Arbitrary!ushort.generate;
    Arbitrary!ushort.specialCases;
    assert(Arbitrary!ushort.shrink(10).take(10).equal([9,8,7,6,5,4,3,2,1,0]));
    
    Arbitrary!short.generate;
    Arbitrary!short.specialCases;
    assert(Arbitrary!short.shrink(10).take(10).equal([9,8,7,6,5,4,3,2,1,0]));
    assert(Arbitrary!short.shrink(-10).take(10).equal([-9,-8,-7,-6,-5,-4,-3,-2,-1,0]));
    
    Arbitrary!uint.generate;
    Arbitrary!uint.specialCases;
    assert(Arbitrary!ushort.shrink(10).take(10).equal([9,8,7,6,5,4,3,2,1,0]));
    
    Arbitrary!int.generate;
    Arbitrary!int.specialCases;
    assert(Arbitrary!int.shrink(10).take(10).equal([9,8,7,6,5,4,3,2,1,0]));
    assert(Arbitrary!int.shrink(-10).take(10).equal([-9,-8,-7,-6,-5,-4,-3,-2,-1,0]));
    
    Arbitrary!ulong.generate;
    Arbitrary!ulong.specialCases;
    assert(Arbitrary!ushort.shrink(10).take(10).equal([9,8,7,6,5,4,3,2,1,0]));
    
    Arbitrary!long.generate;
    Arbitrary!long.specialCases;
    assert(Arbitrary!long.shrink(10).take(10).equal([9,8,7,6,5,4,3,2,1,0]));
    assert(Arbitrary!long.shrink(-10).take(10).equal([-9,-8,-7,-6,-5,-4,-3,-2,-1,0]));
}

/**
*   Arbitrary for float, double
*/
template Arbitrary(T)
    if(isFloatingPoint!T)
{
    static assert(CheckArbitrary!T);
    
    auto generate()
    {
        return (() => Maybe!T(uniform!"[]"(-T.max, T.max))).generator;
    }
    
    auto shrink(T val)
    {
        class Shrinker
        {
            T saved;
            
            this(T firstVal)
            {
                saved = firstVal;
            }
            
            Maybe!T shrink()
            {
                if(cast(long)saved == 0) return Maybe!T.nothing;
                
                if(saved > 0) saved--;
                if(saved < 0) saved++;
                
                return Maybe!T(saved);
            }
        }
        
        return (&(new Shrinker(val)).shrink).generator;
    }
    
    T[] specialCases()
    {
        return [-T.max, 0, T.max, T.nan, T.infinity, T.epsilon, T.min_normal];
    }
}
unittest
{
    import std.math;
    import std.algorithm;
    
    Arbitrary!float.generate;
    Arbitrary!float.specialCases;
    assert(reduce!"a && approxEqual(b[0], b[1])"(true, Arbitrary!float.shrink(10.0).take(10).zip([9,8,7,6,5,4,3,2,1,0])));
    assert(reduce!"a && approxEqual(b[0], b[1])"(true, Arbitrary!float.shrink(-10.0).take(10).zip([-9,-8,-7,-6,-5,-4,-3,-2,-1,0])));
    
    Arbitrary!double.generate;
    Arbitrary!double.specialCases;
    assert(reduce!"a && approxEqual(b[0], b[1])"(true, Arbitrary!double.shrink(10.0).take(10).zip([9,8,7,6,5,4,3,2,1,0])));
    assert(reduce!"a && approxEqual(b[0], b[1])"(true, Arbitrary!double.shrink(-10.0).take(10).zip([-9,-8,-7,-6,-5,-4,-3,-2,-1,0])));
}

/**
*   Arbitrary for bool
*/
template Arbitrary(T)
    if(is(T == bool))
{
    static assert(CheckArbitrary!T);
    
    auto generate()
    {
        return [true, false];
    }
    
    auto shrink(T val)
    {
        return takeNone!(T[]);
    }
    
    auto specialCases()
    {
        return takeNone!(T[]);
    }
}
unittest
{
    assert(Arbitrary!bool.generate.equal([true, false]));
    assert(Arbitrary!bool.shrink(true).empty);
    assert(Arbitrary!bool.shrink(false).empty);
}

/**
*   Arbitrary template for char, dchar, wchar
*/
template Arbitrary(T)
    if(isSomeChar!T)
{
    static assert(CheckArbitrary!T);
    
    auto generate()
    {
        return (() => Maybe!T(cast(T)uniform!"[]"('\u0000', '\U0010FFFF'))).generator;
    }
    
    auto shrink(T val)
    {
        return takeNone!(dchar[]);
    }
    
    auto specialCases()
    {
        return takeNone!(dchar[]);
    }
}
unittest
{
    Arbitrary!char.generate;
    assert(Arbitrary!char.shrink('a').empty);
    assert(Arbitrary!char.specialCases().empty);
    
    Arbitrary!wchar.generate;
    assert(Arbitrary!wchar.shrink('a').empty);
    assert(Arbitrary!wchar.specialCases().empty);
    
    Arbitrary!dchar.generate;
    assert(Arbitrary!dchar.shrink('a').empty);
    assert(Arbitrary!dchar.specialCases().empty);
}

/**
*   Arbitrary template for strings
*/
template Arbitrary(T)
    if(isSomeString!T)
{
    static assert(CheckArbitrary!T);
    
    auto generate()
    {
        return (() => Maybe!T(Arbitrary!(Unqual!(ElementType!T)).generate
                .take(uniform!"[]"(ArrayGenSizeMin, ArrayGenSizeMax)).array.idup.to!T)).generator;
    }
    
    auto shrink(T val)
    {
        class Shrinker
        {
            T saved;
            
            this(T startVal)
            {
                saved = startVal;
            }
            
            auto shrink()
            {
                if(saved.length > 0)
                {
                    saved = saved[1..$];
                    return Maybe!T(saved);
                } else return Maybe!T.nothing;
            }
        }
        return (&(new Shrinker(val)).shrink).generator;
    }
    
    T[] specialCases()
    {
        return [cast(T)""];
    }
}
unittest
{
    Arbitrary!string.generate;
    assert(Arbitrary!string.shrink("a").take(2).equal([""]));
    assert(Arbitrary!string.shrink("abc").take(3).equal(["bc", "c", ""]));
    assert(Arbitrary!string.specialCases().equal([""]));
    
    Arbitrary!wstring.generate;
    assert(Arbitrary!wstring.shrink("a"w).take(2).equal([""w]));
    assert(Arbitrary!wstring.shrink("abc"w).take(3).equal(["bc"w, "c"w, ""w]));
    assert(Arbitrary!wstring.specialCases().equal([""w]));
    
    Arbitrary!dstring.generate;
    assert(Arbitrary!dstring.shrink("a"d).take(2).equal([""d]));
    assert(Arbitrary!dstring.shrink("abc"d).take(3).equal(["bc"d, "c"d, ""d]));
    assert(Arbitrary!dstring.specialCases().equal([""d]));
}