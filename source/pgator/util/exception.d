// Written in D programming language
/**
*   Module handles exception handling functions.
*
*   Copyright: © 2014 DSoftOut
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: Zaramzan <shamyan.roman@gmail.com>
*/
module pgator.util.exception;

/**
* Tries to call function. On exception throws Ex, otherwise return func() result
*
* Authors: Zaramzan <shamyan.roman@gmail.com>
*/
template tryEx(Ex, alias func)
{
    static assert(isSomeFunction!func, "func must be some function");
    
    static assert(is(Ex:Exception), "Ex must be Exception");
    
    alias ReturnType!func T;
    
    alias ParameterTypeTuple!func P;

    T foo(P)(P params)
    {   
        try
        {
            return func(params);
        }
        catch(Exception ex)
        {
            throw new Ex(ex.msg, ex.file, ex.line);
        }
    }
    
    alias foo!P tryEx;
}

/**
* Tries to evaluate par. On exception throws Ex, otherwise return par
*
* Authors: Zaramzan <shamyan.roman@gmail.com>
*/
T tryEx(Ex, T)(lazy T par)
{
    static assert(is(Ex:Exception), "Ex must be Exception");
    
    try
    {
        return par;
    }
    catch(Exception ex)
    {
        throw new Ex(ex.msg, ex.file, ex.line);
    }
}

version(unittest)
{
    bool thrower()
    {
        throw new Exception("Exception");
    }
    
    class TestException: Exception
    {
        @safe pure nothrow this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null)
        {
            super(msg, file, line, next); 
        }
    }
}
unittest
{
    import std.exception;
    
    assertThrown!TestException(tryEx!TestException(thrower()));
}