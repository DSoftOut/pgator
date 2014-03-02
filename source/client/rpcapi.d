// Written in D programming language
/**
*   This module defines rest api to communicate with rpc server.
*
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

struct RpcOk
{
    Json result; // temp
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
    
    RpcOk assertOk()
    {
        scope(failure)
        {
            assert(false, text("Expected successful respond! But got: ", respond));
        }
        
        assert(respond.result.type != Json.Type.undefined);
        return RpcOk(respond.result);
    }
    
    private Json respond;
}