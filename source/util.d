// Written in D programming language
/**
*   Module handles functions and templates that we lazied to factor out to separate module.
*
*   Function categories:
*   <ul>
*   <li> JSON de/serialization based on annotations </li>
*   <li> Exception handling functions </li>
*   <li> Cheat casting functions </li>
*   <li> String processing functions (the only one $(B fromStringz))</li>
*   <li> Introspecting templates that cannot be found in Phobos </li> 
*   <li> Functional styled utilities for optional values and lazy ranges</li> 
*   </ul>
*
*   Copyright: © 2014 DSoftOut
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: Zaramzan <shamyan.roman@gmail.com>, 
*            NCrashed <ncrashed@gmail.com>
*/
module util;

import std.algorithm;
import std.exception;
import std.string;
import std.conv;
import std.container;
import std.traits;
import std.range;
import std.path;
import vibe.data.json;

enum APPNAME = "pgator";

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

/**
* cast to shared type T
*
* Warning:
*	Don't use this, if you want send object to another thread. It just dirty hack.
*/
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

static if (__VERSION__ < 2066) { // from phobos 2.066-b1
	import std.c.string;
	
	/++
	    Returns a D-style array of $(D char) given a zero-terminated C-style string.
	    The returned array will retain the same type qualifiers as the input.
	
	    $(RED Important Note:) The returned array is a slice of the original buffer.
	    The original data is not changed and not copied.
	+/
	
	inout(char)[] fromStringz(inout(char)* cString) @system pure {
	    return cString ? cString[0 .. strlen(cString)] : null;
	}
	
	///
	@system pure unittest
	{
	    assert(fromStringz(null) == null);
	    assert(fromStringz("foo") == "foo");
	}
} else {
	public import std.string: fromStringz;
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

void removeOne(T)(ref DList!T list, T elem)
{
   auto toRemove = list[].find(elem).take(1);
   list.linearRemove(toRemove);
}

/**
*   Struct-wrapper to handle result of computations,
*   that can fail.
*
*   Example:
*   ---------
*   class A {}
*   
*   auto a = new A();
*   auto ma = Maybe!A(a);
*   auto mb = Maybe!A(null);
*   
*   assert(!ma.isNothing);
*   assert(mb.isNothing);
*   
*   assert(ma.get == a);
*   assertThrown!Error(mb.get);
*   
*   bool ncase = false, jcase = false;
*   ma.map(() {ncase = true;}, (v) {jcase = true;});
*   assert(jcase && !ncase);
*   
*   ncase = jcase = false;
*   mb.map(() {ncase = true;}, (v) {jcase = true;});
*   assert(!jcase && ncase);
*   ---------
*/
struct Maybe(T)
    if(is(T == class) || is(T == interface) 
        || isPointer!T || isArray!T) 
{
    private T value;
    
    /// Alias to stored type
    alias T StoredType;
    
    /**
    *   Constructing Maybe from $(B value).
    *   If pointer is $(B null) methods: $(B isNothing) returns true and 
    *   $(B get) throws Error.
    */
    this(T value) pure
    {
        this.value = value;
    }
    
    /**
    *   Constructing empty Maybe.
    *   If Maybe is created with the method, it is considred empty
    *   and $(B isNothing) returns false.
    */
    static Maybe!T nothing()
    {
        return Maybe!T(null);
    } 
    
    /// Returns true if stored value is null
    bool isNothing() const
    {
        return value is null;
    }
    
    /**
    *   Unwrap value from Maybe.
    *   If stored value is $(B null), Error is thrown.
    */
    T get()
    {
        assert(value !is null, "Stored reference is null!");
        return value;
    }
    
    /**
    *   Unwrap value from Maybe.
    *   If stored value is $(B null), Error is thrown.
    */
    const(T) get() const
    {
        assert(value !is null, "Stored reference is null!");
        return value;
    }
    
    /**
    *   If struct holds $(B null), then $(B nothingCase) result
    *   is returned. If struct holds not $(B null) value, then
    *   $(justCase) result is returned. $(B justCase) is fed
    *   with unwrapped value.
    */
    U map(U)(U delegate() nothingCase, U delegate(T) justCase)
    {
        return isNothing ? nothingCase() : justCase(value);
    }
    
    /**
    *   If struct holds $(B null), then $(B nothingCase) result
    *   is returned. If struct holds not $(B null) value, then
    *   $(justCase) result is returned. $(B justCase) is fed
    *   with unwrapped value.
    */
    U map(U)(U delegate() nothingCase, U delegate(const T) justCase) const
    {
        return isNothing ? nothingCase() : justCase(value);
    }
}

unittest
{
    class A {}
    
    auto a = new A();
    auto ma = Maybe!A(a);
    auto mb = Maybe!A(null);
    
    assert(!ma.isNothing);
    assert(mb.isNothing);
    
    assert(ma.get == a);
    assertThrown!Error(mb.get);
    
    bool ncase = false, jcase = false;
    ma.map(() {ncase = true;}, (v) {jcase = true;});
    assert(jcase && !ncase);
    
    ncase = jcase = false;
    mb.map(() {ncase = true;}, (v) {jcase = true;});
    assert(!jcase && ncase);
}

/**
*   Struct-wrapper to handle result of computations,
*   that can fail.
*
*   Example:
*   ---------
*   struct A {}
*   
*   auto ma = Maybe!A(A());
*   auto mb = Maybe!A.nothing;
*   
*   assert(!ma.isNothing);
*   assert(mb.isNothing);
*   
*   assert(ma.get == A());
*   assertThrown!Error(mb.get);
*   
*   bool ncase = false, jcase = false;
*   ma.map(() {ncase = true;}, (v) {jcase = true;});
*   assert(jcase && !ncase);
*   
*   ncase = jcase = false;
*   mb.map(() {ncase = true;}, (v) {jcase = true;});
*   assert(!jcase && ncase);
*   ---------
*/
struct Maybe(T)
    if(is(T == struct) || isAssociativeArray!T || isBasicType!T) 
{
    private bool empty;
    private T value;
    
    /// Alias to stored type
    alias T StoredType;
    
    /**
    *   Constructing empty Maybe.
    *   If Maybe is created with the method, it is considred empty
    *   and $(B isNothing) returns false.
    */
    static Maybe!T nothing()
    {
        Maybe!T ret;
        ret.empty = true;
        return ret;
    } 
    
    /**
    *   Constructing Maybe from $(B value).
    *   If Maybe is created with the constructor, it is considered non empty
    *   and $(B isNothing) returns false.
    */
    this(T value) pure
    {
        this.value = value;
        empty = false;
    }
    
    /// Returns true if stored value is null
    bool isNothing() const
    {
        return empty;
    }
    
    /**
    *   Unwrap value from Maybe.
    *   If the Maybe is empty, Error is thrown.
    */
    T get()
    {
        assert(!empty, "Stored value is null!");
        return value;
    }
    
    /**
    *   Unwrap value from Maybe.
    *   If the Maybe is empty, Error is thrown.
    */
    const(T) get() const
    {
        assert(!empty, "Stored value is null!");
        return value;
    }
    
    /**
    *   If struct holds $(B null), then $(B nothingCase) result
    *   is returned. If struct holds not $(B null) value, then
    *   $(justCase) result is returned. $(B justCase) is fed
    *   with unwrapped value.
    */
    U map(U)(U delegate() nothingCase, U delegate(T) justCase)
    {
        return isNothing ? nothingCase() : justCase(value);
    }
    
    /**
    *   If struct holds $(B null), then $(B nothingCase) result
    *   is returned. If struct holds not $(B null) value, then
    *   $(justCase) result is returned. $(B justCase) is fed
    *   with unwrapped value.
    */
    U map(U)(U delegate() nothingCase, U delegate(const T) justCase) const
    {
        return isNothing ? nothingCase() : justCase(value);
    }
}

unittest
{
    struct A {}
    
    auto ma = Maybe!A(A());
    auto mb = Maybe!A.nothing;
    
    assert(!ma.isNothing);
    assert(mb.isNothing);
    
    assert(ma.get == A());
    assertThrown!Error(mb.get);
    
    bool ncase = false, jcase = false;
    ma.map(() {ncase = true;}, (v) {jcase = true;});
    assert(jcase && !ncase);
    
    ncase = jcase = false;
    mb.map(() {ncase = true;}, (v) {jcase = true;});
    assert(!jcase && ncase);
}

/**
*   Transforms delegate into lazy range. Generation is stopped, when
*   $(B genfunc) returns $(B Maybe!T.nothing).
*
*   Example:
*   --------
*   assert( (() => Maybe!int(1)).generator.take(10).equal(1.repeat.take(10)) );
*   assert( (() => Maybe!int.nothing).generator.empty);
*   assert( (() 
*           {
*               static size_t i = 0;
*               return i++ < 10 ? Maybe!int(1) : Maybe!int.nothing;
*           }
*           ).generator.equal(1.repeat.take(10)));
*   
*   class A {}
*   auto a = new A();
*   
*   assert( (() => Maybe!A(a)).generator.take(10).equal(a.repeat.take(10)) );
*   assert( (() => Maybe!A.nothing).generator.empty);
*   assert( (() 
*           {
*               static size_t i = 0;
*               return i++ < 10 ? Maybe!A(a) : Maybe!A.nothing;
*           }
*           ).generator.equal(a.repeat.take(10)));
*   --------
*/
auto generator(T)(Maybe!T delegate() genfunc)
{
    struct Sequencer
    {
        private Maybe!T currvalue;
        
        T front()
        {
            assert(!currvalue.isNothing, "Generator range is empty!");
            return currvalue.get;
        }
        
        bool empty()
        {
            return currvalue.isNothing;
        }
        
        void popFront()
        {
            currvalue = genfunc();
        }
    }
    static assert(isInputRange!Sequencer);
    
    auto s = Sequencer();
    s.popFront;
    return s;
}
unittest
{
    assert( (() => Maybe!int(1)).generator.take(10).equal(1.repeat.take(10)) );
    assert( (() => Maybe!int.nothing).generator.empty);
    assert( (() 
            {
                static size_t i = 0;
                return i++ < 10 ? Maybe!int(1) : Maybe!int.nothing;
            }
            ).generator.equal(1.repeat.take(10)));
    
    class A {}
    auto a = new A();
    
    assert( (() => Maybe!A(a)).generator.take(10).equal(a.repeat.take(10)) );
    assert( (() => Maybe!A.nothing).generator.empty);
    assert( (() 
            {
                static size_t i = 0;
                return i++ < 10 ? Maybe!A(a) : Maybe!A.nothing;
            }
            ).generator.equal(a.repeat.take(10)));
}
