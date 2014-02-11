// Written in D programming language
/**
* Util module
*
* Authors: Zaramzan <shamyan.roman@gmail.com>, NCrashed <ncrashed@gmail.com>
*
*/
module util;

import std.string;

mixin template t_field(T, alias fieldName)
{
	mixin("private "~T.stringof~" m_"~fieldName~";");
	
	mixin("private bool f_"~fieldName~";");
	
	mixin(T.stringof~" "~fieldName~"() @property { return m_"~fieldName~";}");
	
	mixin("private void "~fieldName~"("~T.stringof~" f) @property { m_"~fieldName~"= f; f_"~fieldName~"=true;}");
}

/// fromStringz
/**
*   Returns new string formed from C-style (null-terminated) string $(D msg). Usefull
*   when interfacing with C libraries. For D-style to C-style convertion use std.string.toStringz
*
*   Example:
*   ----------
*   char[] cstring = "some string".dup ~ cast(char)0;
*
*   assert(fromStringz(cstring.ptr) == "some string");
*   ----------
*/
string fromStringz(const char* msg) nothrow
{
    try
    {
        if(msg is null) return "";

        auto buff = new char[0];
        uint i = 0;
            while(msg[i]!=cast(char)0)
                buff ~= msg[i++];
        return buff.idup;
    } catch(Exception e)
    {
        return "";
    }
}

unittest
{
    char[] cstring = "some string".dup ~ cast(char)0;

    assert(fromStringz(cstring.ptr) == "some string");
}