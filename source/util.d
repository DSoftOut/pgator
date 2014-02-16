// Written in D programming language
/**
* Util module
*
* Authors: Zaramzan <shamyan.roman@gmail.com>, NCrashed <ncrashed@gmail.com>
*
*/
module util;

import std.string;
import std.conv;
import std.traits;
import vibe.data.json;

mixin template t_field(T, alias fieldName)
{
	mixin("private "~T.stringof~" m_"~fieldName~";");
	
	mixin("private bool f_"~fieldName~";");
	
	mixin(T.stringof~" "~fieldName~"() @property { return m_"~fieldName~";}");
	
	mixin("private void "~fieldName~"("~T.stringof~" f) @property { m_"~fieldName~"= f; f_"~fieldName~"=true;}");
}

enum required;
enum possible;


T deserializeFromJson(T)(Json src)
{
	T ret;
	
	static assert (is(T == struct), "Need aggregate type, not "~T.stringof);
	
	if (src.type != Json.Type.object)
	{
		throw new RequiredJsonObject("Required json object");
	}
	
	foreach(mem; __traits(allMembers, T))
	{			
		static if (isRequired!(mem, T) || isOptional!(mem, T))
		{
			if (mixin("src."~mem~".type != Json.Type.undefined"))
			{
				
				static if ((is(typeof(mixin("ret."~mem)) == struct)))
				{
					if (mixin("src."~mem~".type == Json.Type.object"))
					{
						static if ((is(typeof(mixin("ret."~mem)) == Json)))
						{
							mixin("ret."~mem~"=src."~mem~";");
						}	
						else 
						{	
							mixin("ret."~mem~"=deserializeFromJson!(typeof(ret."~mem~"))(src."~mem~");");
						}
					}
				}
				else
				{
					static if (is(typeof(mixin("ret."~mem)) == string[]))
					{
						if (mixin("src."~mem~".type == Json.Type.array"))
						{
							string[] arr = new string[0];
							
							foreach(json; mixin("src."~mem))
							{
								arr ~= json.to!string;
							}
							
							mixin("ret."~mem~"= arr;");
						}		
					}
					else
					{
						static if (is(typeof(mixin("ret."~mem)) == Json))
						{
							mixin("ret."~mem~"=src."~mem~";");
						}
						else
						{
							mixin("ret."~mem~"= src."~mem~".to!(typeof(ret."~mem~"))();");
						}
					}
				 }  
			}
			else
			{ 
				static if (isRequired!(mem, T))
				{
					throw new RequiredFieldException("Field "~mem~" required in json:"~src.toString);
				}
			}
	
		}
		
	}
	
	return ret;
}

static bool isRequired(alias mem, T)()
{
	foreach(attr;__traits(getAttributes, mixin("T."~mem)))
	{
		static if (is(attr == required))
		{
			return true;
		}
	}
	
	return false;
}

static bool isOptional(alias mem, T)()
{
	foreach(attr;__traits(getAttributes, mixin("T."~mem)))
	{
		static if (is(attr == possible))
		{
			return true;
		}
	}
	
	return false;
}

class RequiredFieldException:Exception
{
	this(in string msg)
	{
		super(msg);
	}
}

class RequiredJsonObject:Exception
{
	this(in string msg)
	{
		super(msg);
	}
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