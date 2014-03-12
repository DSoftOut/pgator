// Written in D programming language
/**
*   This module defines rest api to communicate with rpc server.
*
*   Copyright: © 2014 DSoftOut
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module client.rpcapi;

import vibe.data.json;
import vibe.data.serialization;
import std.array;
import std.random;
import std.conv;

interface IRpcApi
{
    Json rpc(string jsonrpc, string method, Json[] params, uint id);
    
    final RpcRespond runRpc(string method, T...)(T params)
    {
        auto builder = appender!(Json[]);
        foreach(param; params)
            builder.put(param.serializeToJson);
        
        return new RpcRespond(rpc("2.0", method, builder.data, uniform(uint.min, uint.max)));    
    }
}

struct RpcError
{
    uint code;
    string message;
}

/**
*   Declares template for holding compile time info
*   about column format: name and element type.
*
*   First column parameter is an element type, second
*   parameter is column name in response.
*
*   Example:
*   ---------
*   alias col = Column!(uint, "column_name");
*   static assert(is(col.type == uint));
*   static assert(col.name == "column_name");
*   ---------
*/
template Column(T...)
{
    static assert(T.length >= 2);
    
    alias T[0] type;
    enum name = T[1];
}
/**
*   Checks is $(B U) actually
*   equal $(B Column) semantic, i.e. holding
*   type and name.
*/
template isColumn(US...)
{
    static if(US.length > 0)
    {
        alias US[0] U;
        
        enum isColumn = __traits(compiles, U.name) && is(typeof(U.name) == string) &&
            __traits(compiles, U.type) && is(U.type);
    } else
    {
        enum isColumn = false;
    }
}
unittest
{
   alias col = Column!(uint, "column_name");
   static assert(is(col.type == uint));
   static assert(col.name == "column_name");
   static assert(isColumn!col);
   static assert(!isColumn!string);
}

/**
*   Structure represents normal response from RPC server
*   with desired columns. Columns element type and name
*   is specified by $(B Column) template.
*/
struct RpcOk(Cols...)
{
    static assert(checkTypes!Cols, "RpcOk compile arguments have to be of type kind: Column!(ColumnType, string ColumnName)");
     
    mixin(genColFields!Cols());
    
    this(Json result)
    {
        auto columns = result.get!(Json[string]);
        foreach(ColInfo; Cols)
        {
            mixin(ColInfo.name~" = columns[\""~ColInfo.name~"\"].deserializeJson!("~ColInfo.type.stringof~"[]);");
        }
    }
    
    // private generation 
    private static string colField(U...)()
    {
        return U[0].type.stringof ~ "[] "~U[0].name~";";
    }
    
    private static string genColFields(U...)()
    {
        string res;
        foreach(ColInfo; U)
        {
            res ~= colField!(ColInfo)()~"\n";
        }
        return res;
    }
    
    private template checkTypes(U...)
    {
        static if(U.length == 0)
            enum checkTypes = true;
        else
            enum checkTypes = isColumn!(U[0]) && checkTypes!(U[1..$]); 
    }
}

class RpcRespond
{
    this(Json respond)
    {
        this.respond = respond;
    }
    
    RpcError assertError()
    {
        scope(failure)
        {
            assert(false, text("Expected respond with error! But got: ", respond));
        }
        
        return RpcError(respond.code.get!uint, respond.message.get!string);
    }
    
    RpcOk!RowTypes assertOk(RowTypes...)()
    {
        scope(failure)
        {
            assert(false, text("Expected successful respond! But got: ", respond));
        }
        
        assert(respond.result.type != Json.Type.undefined);
        return RpcOk!RowTypes(respond.result.get!(Json[])[0]);
    }
    
    private Json respond;
}