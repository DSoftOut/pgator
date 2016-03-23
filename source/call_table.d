module pgator.rpc_table;

import dpq2.result;
import vibe.core.log;

struct Method
{
    string name; // TODO: remove it, AA already contains name of method
    Statement[] statements;
    bool isMultiStatement = false;
    bool readOnlyFlag = false; // TODO: rename to isReadOnly
    bool needAuthVariablesFlag = false; /// pass username and password from HTTP session to SQL session
}

struct Statement
{
    short statementNum = -1;

    // Required parameters:
    string sqlCommand;
    string[] argsNames;
    OidType[] argsOids;
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

        void getOptionalField(T)(string sqlName, ref T result)
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
            logFatal(e.msg~", failed on method "~m.name);
            break;
        }

        // Reading of optional parameters
        try
        {
            getOptionalField("read_only", m.readOnlyFlag);
            getOptionalField("set_auth_variables", m.needAuthVariablesFlag);

            {
                try
                {
                    if(!r["statement_num"].isNull) s.statementNum = r["statement_num"].as!short;
                }
                catch(AnswerException e)
                {
                    if(e.type != ExceptionType.COLUMN_NOT_FOUND) throw e;
                }

                if(s.statementNum >= 0)
                {
                    m.isMultiStatement = true;
                    getOptionalField("result_name", s.resultName);
                }
            }

            {
                string resultFormatStr = "TABLE";
                getOptionalField("result_format", resultFormatStr);

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
                        if(s.statementNum >= 0)
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
                if(s.statementNum < 0)
                {
                    throw new Exception("Duplicate method "~m.name, __FILE__, __LINE__);
                }
                else // Insert sorted by statementNum
                {
                    import std.array: insertInPlace;
                    import std.conv: to;

                    foreach(const i; 0 .. method.statements.length)
                    {
                        const storedSNum = method.statements[i].statementNum;

                        if(storedSNum == s.statementNum)
                            throw new Exception("Duplicate statement nums "~s.statementNum.to!string~" for method "~m.name, __FILE__, __LINE__);

                        if(i == method.statements.length - 1)
                            method.statements ~= s;

                        if(storedSNum > s.statementNum)
                        {
                            method.statements.insertInPlace(i, s);
                            break;
                        }
                    }
                }
            }
        }

        ret.loaded++;

        logDebugV("Method "~m.name~" loaded");
    }

    return ret;
}
