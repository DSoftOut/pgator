// Written in D programming language
/**
*    Part of asynchronous pool realization.
*    
*    Copyright: © 2014 DSoftOut
*    License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*    Authors: NCrashed <ncrashed@gmail.com>
*/
module db.async.respond;

import db.connection;
import db.pq.api;
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
    this(QueryException e)
    {
        failed = true;
        exception = e.msg;
    }
    
    /**
    *   Transforms raw result from data base into BSON format. Also handles
    *   errors that was raised in the connection.
    */
    bool collect(InputRange!(shared IPGresult) results, shared IConnection conn)
    {
        foreach(res; results)
        {
            if( res.resultStatus != ExecStatusType.PGRES_TUPLES_OK &&
                res.resultStatus != ExecStatusType.PGRES_COMMAND_OK)
            {
                failed = true;
                exception = res.resultErrorMessage;
                return false;
            }
            result ~= res.asColumnBson(conn);
            res.clear();
        }
        return true;
    }
    
    /// Flag to distinct error case from normal respond
    bool failed = false;
    /// Error stored in string
    string exception;
    /// Collected result
    immutable(Bson)[] result;
}