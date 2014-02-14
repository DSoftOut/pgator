// Written in D programming language
/**
*    Authors: NCrashed <ncrashed@gmail.com>
*/
module db.table;

import std.container;
import db.pq.api;

struct RawTable
{
    string[] columns;
    string[][] rows; 
    
    invariant()
    {
        auto s = columns.length;
        foreach(ref row; rows)
            assert(row.length == s);
    }
}

/**
*   Converts PostgreSQL table into intermediate format. 
*   TODO: converting binary data into the string representation.
*/
RawTable convertResult(const shared IPGresult res)
{
    immutable fieldsCount = res.nfields;
    immutable rowsCount   = res.ntuples;
    
    RawTable table;
    table.columns = new string[fieldsCount];
    foreach(i, ref name; table.columns)
        name = res.fname(i);
        
    table.rows = new string[][rowsCount];
    foreach(i, ref row; table.rows)
    {
        row = new string[fieldsCount];
        foreach(j; 0..fieldsCount)
            row[j] = res.asString(i, j);
    }
    
    return table;
}