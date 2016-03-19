module pgator.rpc_table;

import dpq2.result;
import vibe.core.log;

struct Method
{
    string name; // TODO: remove it, AA already contains name of method
    Statement[] statements;
    bool isMultiStatement = false;
    bool readOnlyFlag = false;
    bool needAuthVariablesFlag = false; /// pass username and password from HTTP session to SQL session
}

struct Statement // TODO: rename to statement
{
    // Required parameters:
    string preparedStatementName;
    string sqlCommand;
    string[] argsNames;
    OidType[] argsOids;

    // Optional parameters:
    string resultName;
    ResultFormat resultFormat = ResultFormat.TABLE;
}

enum ResultFormat
{
    TABLE,
    ROTATED, /// rotate result "counterclockwise"
    ROW,
    CELL, /// one cell result
    VOID /// Run without result (only for multi-statement methods)
}

struct ReadMethodsResult
{
    Method[string] methods;
    size_t loaded;
}

ReadMethodsResult readMethods(immutable Answer answer)
{
    ReadMethodsResult ret;

    foreach(ref r; rangify(answer))
    {
        debug logDebugV("found row: "~r.toString);

        // optional params handler
        void getOptional(T)(string sqlName, ref T result)
        {
            try
            {
                auto v = r[sqlName];

                if(v.isNull)
                    throw new Exception("Value of column "~sqlName~" is NULL", __FILE__, __LINE__);

                result = v.as!T;
            }
            catch(AnswerException e)
            {
                if(e.type != ExceptionType.COLUMN_NOT_FOUND) throw e;
            }
        }

        Statement s;
        Method m;
        short statementNum = -1;

        // Reading of required parameters
        try
        {
            if(r["method"].isNull)
                throw new Exception("Method name is NULL", __FILE__, __LINE__);

            m.name = r["method"].as!string;

            if(m.name.length == 0)
                throw new Exception("Method name is empty", __FILE__, __LINE__);

            if(r["sql_query"].isNull)
                throw new Exception("sql_query is NULL", __FILE__, __LINE__);

            s.sqlCommand = r["sql_query"].as!string;

            if(r["args"].isNull)
            {
                throw new Exception("args[] is NULL", __FILE__, __LINE__);
            }
            else
            {
                auto arr = r["args"].asArray;

                if(arr.dimsSize.length > 1)
                    throw new Exception("args[] should be one dimensional", __FILE__, __LINE__);

                foreach(ref v; rangify(arr))
                {
                    if(v.isNull || v.as!string.length == 0)
                        throw new Exception("args[] contains NULL or empty string", __FILE__, __LINE__);

                    s.argsNames ~= v.as!string;
                }
            }
        }
        catch(Exception e)
        {
            logFatal(e.msg, ", failed on method ", m.name);
            break;
        }

        // Reading of optional parameters
        try
        {
            getOptional("read_only", m.readOnlyFlag);
            getOptional("set_auth_variables", m.needAuthVariablesFlag);

            {
                try
                {
                    if(!r["statement_num"].isNull) statementNum = r["statement_num"].as!short;
                }
                catch(AnswerException e)
                {
                    if(e.type != ExceptionType.COLUMN_NOT_FOUND) throw e;
                }

                if(statementNum < 0)
                {
                    s.preparedStatementName = m.name;
                }
                else
                {
                    getOptional("result_name", s.resultName);

                    import std.conv: to;
                    s.preparedStatementName = m.name~"_"~statementNum.to!string;

                    m.isMultiStatement = true;
                }
            }

            {
                string resultFormatStr;
                getOptional("result_format", resultFormatStr);

                switch(resultFormatStr)
                {
                    case "TABLE":
                        s.resultFormat = ResultFormat.TABLE;
                        break;

                    case "ROTATED":
                        s.resultFormat = ResultFormat.ROTATED;
                        break;

                    case "ROW":
                        s.resultFormat = ResultFormat.ROW;
                        break;

                    case "CELL":
                        s.resultFormat = ResultFormat.CELL;
                        break;

                    case "VOID":
                        if(statementNum >= 0)
                        {
                            s.resultFormat = ResultFormat.VOID;
                        }
                        else
                        {
                            throw new Exception("result_format=VOID only for multi-statement transactions", __FILE__, __LINE__);
                        }
                        break;

                    default:
                        throw new Exception("Unknown result format type "~resultFormatStr, __FILE__, __LINE__);
                }
            }
        }
        catch(Exception e)
        {
            logWarn("Skipping "~m.name~": "~e.msg);
            continue;
        }

        {
            auto method = m.name in ret.methods;

            if(method is null)
            {
                m.statements ~= s;
                ret.methods[m.name] = m;
            }
            else
            {
                method.statements ~= s;
            }
        }

        ret.loaded++;

        logDebugV("Method "~m.name~" loaded");
    }

    return ret;
}
