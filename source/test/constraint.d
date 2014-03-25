// Written in D programming language
/**
*   Module defines routines for checking constraints in automated mode.
*   
*   To perform automated check user should define a delegate, that takes
*   some arguments and by design should return always true. The $(B checkConstraint)
*   function generates arguments via $(B Arbitrary!T) template and checks the
*   delegate to be true.
*
*   If constrained returned false, $(B checkConstraint) function tries to 
*   shrink input parameters to find minimum fail case (of course, it shrink
*   function of corresponding Arbitrary template is properly defined).
*
*   Example:
*   ---------
*   checkConstraint!((int a, int b) => a + b == b + a);
*   assertThrown!Error(checkConstraint!((int a, int b) => abs(a) < 100 && abs(b) < 100));
*   assertThrown!Error(checkConstraint!((bool a, bool b) => a && !b));
*   ---------
*
*   Copyright: © 2014 DSoftOut
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module test.constraint;

import std.algorithm;
import std.array;
import std.traits;
import std.conv;
import std.range;
import std.stdio;
import test.arbitrary;

private template allHasArbitrary(T...)
{
    static if(T.length == 0)
    {
        enum allHasArbitrary = true;
    } else
    {
        enum allHasArbitrary = HasArbitrary!(T[0]).isFullDefined!() && allHasArbitrary!(T[1..$]);
    }
}

/**
*   Checks $(B constraint) to return true value for random generated input parameters
*   with $(B Arbitrary) template. 
*
*   All input arguments of the constraint have to implement $(B Arbitrary) template.
*   Argument shrinking is performed if parameter corresponding shrink range is not empty.
*
*   If constrained returns false for some parameters set, shrinking is performed and
*   detailed information about the set is thrown with $(B Error).
*
*   $(B testCount) parameter defines maximum count of test run. Test can end early if
*   there is fail or all possible parameters values are checked.
*
*   $(B shrinkCount) parameter defines maximum count of shrinking tries. User implementation
*   of $(B Arbitrary!T.shrink) function defines speed of minimum fail set search, shrinking
*   isn't performed for empty shrinking ranges. 
*/
void checkConstraint(alias constraint)(size_t testsCount = 100, size_t shrinkCount = 100)
    if(isSomeFunction!constraint && allHasArbitrary!(ParameterTypeTuple!constraint))
{
    // generates string of applying constaint with range values
    string genApply(string var)
    {
        string res = "bool "~var~" = constraint(";
        foreach(j, T; ParameterTypeTuple!constraint)
        {
            res ~= "range"~j.to!string~".front,";
        }
        return res~");";
    }
    
    // generates string for declaring range variables
    string genDeclare()
    {
        string res = "";
        foreach(j, T; ParameterTypeTuple!constraint)
        {
            res ~= "auto range"~j.to!string~" = Arbitrary!("~T.stringof~").generate;\n";
            res ~= "assert(!range"~j.to!string~".empty, \"Generating range is empty at checking start!"
                "Check Arbitrary!"~T.stringof~" implementation!\")\n;";
        }
        return res;
    }
    
    // generates string for declaring shrink range variables
    string genShrinkDeclare()
    {
        string res = "";
        foreach(j, T; ParameterTypeTuple!constraint)
        {
            res ~= "auto shrink"~j.to!string~" = Arbitrary!("~T.stringof~").shrink(range"~j.to!string~".front);\n";
            res ~= "ElementType!(typeof(shrink"~j.to!string~")) savedShrink"~j.to!string~" = range"~j.to!string~".front;\n";
        }
        return res;
    }
    
    // generates string of applying constaint with range values
    string genShrinkApply(string var)
    {
        string res = "bool "~var~" = constraint(";
        foreach(j, T; ParameterTypeTuple!constraint)
        {
            res ~= "savedShrink"~j.to!string~",";
        }
        return res~");";
    }
    
    mixin(genDeclare());
    
    // i-th cell holds info about: if i-th range ever be empty
    // testing is ended when all ranges is cycled or max test count is expired
    bool[ParameterTypeTuple!constraint.length] flags;
    // chooses which range is popping now
    size_t k = 0; 
    
    testloop: foreach(calls; 0..testsCount)
    {
        mixin(genApply("res"));
        
        // catched a bug, start shrink
        if(!res)
        {
            size_t shrinks, shrinkOrder;
            bool[ParameterTypeTuple!constraint.length] shrinkFlags;
            mixin(genShrinkDeclare());
            
            void printFinalMessage()
            {
                auto builder = appender!string;
                builder.put("\n==============================\n");
                builder.put(text("Constraint ", constraint.stringof, " is failed!\n"));
                builder.put(text("Calls count: ", calls+1, ". Shrinks count: ", shrinks, "\n"));
                builder.put(text("Parameters: \n"));
                alias ParameterIdentifierTuple!constraint paramNames;
                foreach(j, T; ParameterTypeTuple!constraint)
                {
                    builder.put(text("\t",j,": ", T.stringof, " ",  paramNames[j].stringof, " ",
                            " = ", mixin("savedShrink"~j.to!string~".to!string"), "\n"));
                }
                assert(false, builder.data);
            }
            
            shrinkloop: for(;shrinks < shrinkCount; shrinks++)
            {
                // check shrink ranges
                foreach(j, T; ParameterTypeTuple!constraint)
                {
                    mixin("if (shrink"~j.to!string~".empty)
                        {
                            shrinkFlags["~j.to!string~"] = true;
                        }
                    ");
                }
                if(shrinkFlags.reduce!"a && b")
                {
                    break shrinkloop;
                }
                
                // save values to show them after and
                foreach(j, T; ParameterTypeTuple!constraint)
                {
                    mixin("if (!shrink"~j.to!string~".empty)
                        {
                            savedShrink"~j.to!string~" = shrink"~j.to!string~".front;
                            shrink"~j.to!string~".popFront();
                        }"
                    );
                }
                
                mixin(genShrinkApply("shrinkedRes"));
                
                // displaying result
                if(shrinkedRes)
                {
                    printFinalMessage();
                }
                
                // update shrinkOrder
                shrinkOrder+=1;
                if(shrinkOrder >= ParameterTypeTuple!constraint.length)
                {
                    shrinkOrder = 0;
                }
            }
            
            // displaying result
            printFinalMessage();
        }
        
        // updating ranges in order of k
        foreach(j, T; ParameterTypeTuple!constraint)
        {
            if(j == k)
            {
                mixin("range"~j.to!string~".popFront;");
                mixin("if (range"~j.to!string~".empty) "
                    "{
                        flags["~j.to!string~"] = true;
                        range"~j.to!string~" = Arbitrary!("~T.stringof~").generate;
                    }"
                );
            }
            
            if(flags.reduce!"a && b")
            {
                break testloop;
            }
        }
        // update k
        k+=1;
        if(k >= ParameterTypeTuple!constraint.length)
        {
            k = 0;
        }
    }
}
unittest
{
    import std.math;
    import std.exception;
    
    checkConstraint!((int a, int b) => a + b == b + a);
    assertThrown!Error(checkConstraint!((int a, int b) => abs(a) < 100 && abs(b) < 100));
    assertThrown!Error(checkConstraint!((bool a, bool b) => a && !b));
}