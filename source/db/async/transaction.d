// Written in D programming language
/**
*    Part of asynchronous pool realization.
*    
*    Copyright: © 2014 DSoftOut
*    License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*    Authors: NCrashed <ncrashed@gmail.com>
*/
module db.async.transaction;

import db.pool;
import std.exception;

/**
*   Handles all data that is need to perform SQL transaction: queries, parameters,
*   info where to put parameters and local enviroment variables.
*/
class Transaction : IConnectionPool.ITransaction
{
    this(string[] commands, string[] params, uint[] argnums, string[string] vars) immutable
    {
        this.commands = commands.idup;
        this.params = params.idup;
        this.argnums = argnums.idup;
        string[string] temp = vars.dup;
        this.vars = assumeUnique(temp);
    }
    
    override bool opEquals(Object o) nothrow 
    {
        auto b = cast(Transaction)o;
        if(b is null) return false;
        
        return commands == b.commands && params == b.params && argnums == b.argnums && vars == b.vars;
    }
    
    override hash_t toHash() nothrow @trusted
    {
        hash_t toHashArr(T)(immutable T[] arr) nothrow
        {
            hash_t h;
            auto hashFunc = &(typeid(T).getHash);
            foreach(elem; arr) h += hashFunc(&elem);
            return h;
        }
        
        hash_t toHashAss(T)(immutable T[T] arr) nothrow
        {
            hash_t h;
            scope(failure) return 0;
            auto hashFunc = &(typeid(T).getHash);
            foreach(key, val; arr) h += hashFunc(&key) + hashFunc(&val);
            return h;
        }
        
        return toHashArr(commands) + toHashArr(params) + toHashArr(argnums) + toHashAss(vars);
    }
    
    immutable string[] commands;
    immutable string[] params;
    immutable uint[]   argnums;
    immutable string[string] vars;
}