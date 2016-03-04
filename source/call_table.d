module pgator.rpc_table;

import dpq2.result;
import std.experimental.logger;

struct Method
{
    // Required parameters:
    string name; // TODO: remove it, AA already contains name of method
    string statement;
    string[] argsNames;

    // Optional parameters:
    bool rotateFlag = false; /// rotate result "counterclockwise"
    bool oneRowFlag = false;
}

Method[string] readMethods(immutable Answer answer)
{
    Method[string] methods;

    foreach(ref r; rangify(answer))
    {
        trace("found row: ", r);

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
            fatal(e.msg, ", failed on method ", m.name);
            break;
        }

        // Reading of optional parameters
        try
        {
            getOptional("rotate", m.rotateFlag);
            getOptional("one_row_flag", m.oneRowFlag);
        }
        catch(Exception e)
        {
            warning(e.msg, ", skipping reading of method ", m.name);
            continue;
        }

        methods[m.name] = m;
        info("Method ", m.name, " loaded. Content: ", m);
    }

    return methods;
}
