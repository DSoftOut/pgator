// Written in D programming language
/**
*    Part of asynchronous pool realization.
*    
*    Copyright: © 2014 DSoftOut
*    License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*    Authors: NCrashed <ncrashed@gmail.com>
*/
module pgator.db.async.respond;

import pgator.db.connection;
import pgator.db.pq.api;
import vibe.data.bson;
import std.container;
import std.range;
import derelict.pq.pq;

/// Worker returns this as query result
struct Respond
{
    /// Constructing from error
    /**
    *   The constructor is used when pool detects problem
    *   at its own level. $(B collect) method handles other
    *   cases.
    */
    this(QueryException e, shared IConnection conn)
    {
        scope(exit) conn.clearRaisedMsgs;
        
        failed = true;
        exception = e.msg;
        msgs = conn.raisedMsgs.array.idup;
    }
    
    /**
    *   Transforms raw result from data base into BSON format. Also handles
    *   errors that was raised in the connection.
    */
    bool collect(InputRange!(shared IPGresult) results, shared IConnection conn, bool oneRowConstraint, size_t queryId)
    {
        scope(exit) conn.clearRaisedMsgs;
        msgs ~= conn.raisedMsgs.array.idup;
        
        bool localSucc = true;
        foreach(res; results)
        {
            if( res.resultStatus != ExecStatusType.PGRES_TUPLES_OK &&
                res.resultStatus != ExecStatusType.PGRES_COMMAND_OK)
            {
                failed = true;
                exception = res.resultErrorMessage;
                localSucc = false;
            }
            if(localSucc)
            {
                auto temp = res.asColumnBson(conn);
                if(oneRowConstraint && !isOneRow(temp))
                {
                   failed = true;
                   onRowConstaintFailed = true;
                   constraintFailQueryId = queryId;
                   localSucc = false;
                } else
                {
                    result ~= temp;
                }
            }
            res.clear();
        }
        return localSucc;
    }
    
    private bool isOneRow(Bson res)
    {
        Bson[string] columns;
        try
        {
            columns = res.get!(Bson[string]);
        } 
        catch(Exception e)
        {
            // something wrong with columns
            return false;
        }
        
        foreach(col; columns) return col.length == 1;
        return false;
    }
    
    /// Flag to distinct error case from normal respond
    bool failed = false;
    
    bool onRowConstaintFailed = false;
    size_t constraintFailQueryId;
    
    /// Error stored in string
    string exception;
    /// Collected result
    immutable(Bson)[] result;
    /// Additional messages
    immutable(string)[] msgs;
}