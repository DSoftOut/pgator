module pgator.rpc_table;

import dpq2.result;
import vibe.core.log;

struct Method
{
    // Required parameters:
    string name; // TODO: remove it, AA already contains name of method
    string statement;
    string[] argsNames;
    OidType[] argsOids;

    // Optional parameters:
    short statementNum = -1;
    string resultName;
    ResultFormat resultFormat = ResultFormat.TABLE;
    bool readOnlyFlag = false;
    bool needAuthVariablesFlag = false; /// pass username and password from HTTP session to SQL session
}

enum ResultFormat
{
    TABLE,
    ROTATED, /// rotate result "counterclockwise"
    ROW,
    CELL, /// one cell result
    VOID /// Run without result (only for multi-statement methods)
}

Method[string] readMethods(immutable Answer answer)
{
    Method[string] methods;

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

        Method m;

        // Reading of required parameters
        try
        {
            if(r["method"].isNull)
                throw new Exception("Method name is NULL", __FILE__, __LINE__);

            m.name = r["method"].as!string;

            if(m.name.length == 0)
                throw new Exception("Method name is empty string", __FILE__, __LINE__);

            if(r["sql_query"].isNull)
                throw new Exception("sql_query is NULL", __FILE__, __LINE__);

            m.statement = r["sql_query"].as!string;

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

                    m.argsNames ~= v.as!string;
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
                    if(!r["statement_num"].isNull) m.statementNum = r["statement_num"].as!short;
                    if(!r["result_name"].isNull) m.resultName = r["result_name"].as!string;
                }
                catch(AnswerException e)
                {
                    if(e.type != ExceptionType.COLUMN_NOT_FOUND) throw e;
                }

                if(m.statementNum != -1 && m.resultName.length == 0)
                    throw new Exception("forgotten result_name value", __FILE__, __LINE__);
            }

            {
                string s;
                getOptional("result_format", s);

                switch(s)
                {
                    case "TABLE":
                        m.resultFormat = ResultFormat.TABLE;
                        break;

                    case "ROTATED":
                        m.resultFormat = ResultFormat.ROTATED;
                        break;

                    case "ROW":
                        m.resultFormat = ResultFormat.ROW;
                        break;

                    case "CELL":
                        m.resultFormat = ResultFormat.CELL;
                        break;

                    case "VOID":
                        if(m.statementNum != -1)
                        {
                            m.resultFormat = ResultFormat.VOID;
                        }
                        else
                        {
                            throw new Exception("result_format=VOID only for multi-statement transactions"~s, __FILE__, __LINE__);
                        }
                        break;

                    default:
                        throw new Exception("Unknown result format type "~s, __FILE__, __LINE__);
                }
            }
        }
        catch(Exception e)
        {
            logWarn("Skipping "~m.name~": "~e.msg);
            continue;
        }

        methods[m.name] = m;
        logDebugV("Method "~m.name~" loaded");
    }

    return methods;
}
