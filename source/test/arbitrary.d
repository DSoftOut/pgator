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
                isInputRange!RetType && is(ElementType!RetType == T)
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
                isInputRange!RetType && is(ElementType!RetType == T)
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

/// TODO: finish range generation from pure function
/**
*   Arbitrary for ubyte, byte, ushort, short, uing, int, ulong, long.
*/
template Arbitrary(T)
    if(isIntegral!T)
{
    static assert(CheckArbitrary!T);
    
    T[] generate()
    {
        return [];
    }
    
    T[] shrink(T val)
    {
        return [];
    }
    
    T[] specialCases()
    {
        return [];
    }
}