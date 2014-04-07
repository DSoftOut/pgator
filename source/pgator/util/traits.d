// Written in D programming language
/**
*   Module that handles introspecting templates that cannot be found in Phobos.
*
*   Copyright: © 2014 DSoftOut
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module pgator.util.traits;

import std.traits;

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