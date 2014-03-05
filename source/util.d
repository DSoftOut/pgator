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
import std.range;
import std.path;
import vibe.data.json;

enum APPNAME = "rpc-sql-proxy";

mixin template t_field(T, alias fieldName)
{
	mixin("private "~T.stringof~" m_"~fieldName~";");
	
	mixin("private bool f_"~fieldName~";");
	
	mixin(T.stringof~" "~fieldName~"() @property { return m_"~fieldName~";}");
	
	mixin("private void "~fieldName~"("~T.stringof~" f) @property { m_"~fieldName~"= f; f_"~fieldName~"=true;}");
}

//For deserializeFromJson
enum required;

//For deserializeFromJson
enum possible;


/**
* Deserializes from Json to type T<br>
*
* Supported only structs yet
*
* Example:
* ----
* struct S
* {
*    @required
*	int a; //get value from Json. Throws RequiredFieldException
*
*    @possible
*	int b; //tries to get value from Json
*
*	int c; //will be ignored
* }
*
* auto s = deserializeFromJson!S(json);
* ------
*
* Authors: Zaramzan <shamyan.roman@gmail.com>
*/
T deserializeFromJson(T)(Json src)
{
	T ret;
	
	static assert (is(T == struct), "Need struct type, not "~T.stringof);
	
	if (src.type != Json.Type.object)
	{
		throw new RequiredJsonObject("Required json object");
	}
	
	foreach(mem; __traits(allMembers, T))
	{	
		alias getMemberType!(T, mem) MemType;
				
		static if (isRequired!(mem, T) || isOptional!(mem, T))
		{
			if (mixin("src."~mem~".type != Json.Type.undefined"))
			{
				
				static if (is(MemType == struct))
				{
					static if (is(MemType == Json))
					{
						mixin("ret."~mem~"=src."~mem~";");
					}
					else
					{
						if (mixin("src."~mem~".type == Json.Type.object"))
						{	
							mixin("ret."~mem~"=deserializeFromJson!(typeof(ret."~mem~"))(src."~mem~");");
						}
						else
						{
							throw new RequiredFieldException("Field "~mem~" must be object in json"~src.toString); 
						}
					}
				}
				else
				{
					static if (isArray!MemType && !isSomeString!MemType)
					{
						if (mixin("src."~mem~".type == Json.Type.array"))
						{
							alias ElementType!MemType ElemType;
							
							ElemType[] arr = new ElemType[0];
							
							foreach(json; mixin("src."~mem))
							{
								static if (is(ElemType == struct))
								{
									arr ~= deserializeFromJson!ElemType(json);
								}
								else
								{
									arr ~= json.to!ElemType;
								}
							}
							
							mixin("ret."~mem~"= arr;");
						}
						else
						{
							throw new RequiredFieldException("Field "~mem~" must be array in json"~src.toString);
						}		
					}
					else
					{
						mixin("ret."~mem~"= src."~mem~".to!(typeof(ret."~mem~"))();");
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

/**
* Serializes struct with $(B @required) attributes fields to Json  <br>
* 
* Example
* ------
* struct S
* {
*    @required
*	int a = 1; //will be used
*
*    @possible
*	int b = 2; //will be ignored
*
*	int c; //will be ignored
* }
*
* writeln(serializeRequiredToJson(S())); // { "a":1 }
* ------
*/
Json serializeRequiredToJson(T)(T val)
{
	static assert (is(T == struct), "Need struct type, not "~T.stringof);
	
	Json ret = Json.emptyObject;
	
	foreach(mem; __traits(allMembers, T))
	{
		static if (isRequired!(mem, T))
		{
			alias getMemberType!(T, mem) MemType;
			
			alias vibe.data.json.serializeToJson vibeSer;
			
			static if (is(MemType == struct))
			{
				ret[mem] = serializeRequiredToJson!MemType(mixin("val."~mem));
			}
			else static if (isArray!MemType)
			{
				alias ElementType!MemType EType;
				static if (is(EType == struct))
				{
					auto j1 = Json.emptyArray;
				
					foreach(elem; mixin("val."~mem))
					{
						j1 ~= serializeRequiredToJson(elem);
					}
					
					ret[mem] = j1;
				}
				else
				{
					ret[mem] = vibeSer(mixin("val."~mem));
				}
			}
			else
			{
				ret[mem] = vibeSer(mixin("val."~mem));
			}
		}
	}
	
	return ret;
}

private bool isRequired(alias mem, T)()
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

private bool isOptional(alias mem, T)()
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

/// tries to call function. On exception throws Ex, otherwise return func() result
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

/// tries to evaluate par. On exception throws Ex, otherwise return par
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

/// cast to shared type T
template toShared(T)
{
	private alias Unqual!T P;
	
	shared(P) toShared(T par)
	{
		return cast(shared P) cast(P) par;
	}
}

/// cast to unqual type T
template toUnqual(T)
{
	private alias Unqual!T P;
	
	P toUnqual(T par)
	{
		return cast(P) par;
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

/// getMemberType
/**
*   Retrieves member type with $(D name) of class $(D Class). If member is agregate 
*   type declaration or simply doesn't exist, retrieves no type. You can check it with
*   $(D is) operator.
*
*   Example:
*   -----------
*   class A 
*   {
*       int aField;
*       string b;
*       bool c;
*       
*       class B {}
*       struct C {}
*       union D {}
*       interface E {}
*   }
*
*   static assert(is(getMemberType!(A, "aField") == int));
*   static assert(is(getMemberType!(A, "b") == string));
*   static assert(is(getMemberType!(A, "c") == bool));
*
*   static assert(!is(getMemberType!(A, "B")));
*   static assert(!is(getMemberType!(A, "C")));
*   static assert(!is(getMemberType!(A, "D")));
*   static assert(!is(getMemberType!(A, "E")));
*   -----------
*/
template getMemberType(Class, string name)
{
    static if(hasMember!(Class, name))
        alias typeof(__traits(getMember, Class, name)) getMemberType;
}

unittest
{
    class A 
    {
        int a;
        string b;
        bool c;

        class B {}
        struct C {}
        union D {}
        interface E {}
    }

    static assert(is(getMemberType!(A, "a") == int));
    static assert(is(getMemberType!(A, "b") == string));
    static assert(is(getMemberType!(A, "c") == bool));

    static assert(!is(getMemberType!(A, "B")));
    static assert(!is(getMemberType!(A, "C")));
    static assert(!is(getMemberType!(A, "D")));
    static assert(!is(getMemberType!(A, "E")));
}

/// FieldNameTuple
/**
*   Retrieves names of all class/struct/union $(D Class) fields excluding technical ones like this, Monitor.
*
*   Example:
*   ---------
*   class A 
*   {
*       int aField;
*
*       void func1() {}
*       static void func2() {}
*
*       string b;
*
*       final func3() {}
*       abstract void func4();
*
*       bool c;
*   }
*
*   static assert(FieldNameTuple!A == ["aField","b","c"]);
*   ---------
*/
template FieldNameTuple(Class)
{
    template removeFuncs(funcs...)
    {
        static if(funcs.length > 0)
        {
            // if member is class/struct/interface declaration second part getMemberType returns no type
            static if( is(getMemberType!(Class, funcs[0]) == function) ||
                !is(getMemberType!(Class, funcs[0])) ||
                funcs[0] == "this" || funcs[0] == "Monitor" || funcs[0] == "__ctor" ||
                funcs[0] == "opEquals" || funcs[0] == "opCmp" || funcs[0] == "opAssign")
            {
                enum removeFuncs = removeFuncs!(funcs[1..$]);
            }
            else
                enum removeFuncs = [funcs[0]]~removeFuncs!(funcs[1..$]);
        }
        else
            enum removeFuncs = [];
    }

    enum temp = removeFuncs!(__traits(allMembers, Class));
    static if(temp.length > 0)
        enum FieldNameTuple = temp[0..$-1];
    else
        enum FieldNameTuple = [];
}

// ddoc example
unittest
{
    class A 
    {
        int a;

        void func1() {}
        static void func2() {}

        string b;

        final func3() {}
        abstract void func4();

        bool c;
    }

    static assert(FieldNameTuple!A == ["a","b","c"]);
}
unittest
{
    class P 
    {
        void foo() {}

        real p;
    }

    class A : P
    {
        int aField;

        void func1() {}
        static void func2() {}

        string b;

        final void func3() {}
        abstract void func4();

        bool c;

        void function(int,int) da;
        void delegate(int, int) db;

        class B {} 
        B mB;

        struct C {}
        C mC;

        interface D {}
    }

    static assert(FieldNameTuple!A == ["aField","b","c","da","db","mB","mC","p"]);
    static assert(is(getMemberType!(A, "aField") == int));
    static assert(is(getMemberType!(A, "b") == string));
    static assert(is(getMemberType!(A, "c") == bool));

    struct S1
    {
        int a;
        bool b;

        void foo() {}

        real c;
    }

    static assert(FieldNameTuple!S1 == ["a","b","c"]);

    union S2
    {
        size_t index;
        void*   pointer;
    }

    static assert(FieldNameTuple!S2 == ["index", "pointer"]);

    class S3
    {

    }
    static assert(FieldNameTuple!S3 == []);

    // Properties detected as field. To fix.
    struct S4
    {
        @property S4 dup()
        {
            return S4();
        }
    }
    static assert(FieldNameTuple!S4 == ["dup"]);
}