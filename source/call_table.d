module call_table;

import dpq2.result;
import std.experimental.logger;

struct Method
{
    string name; // TODO: remove it, AA already contains name of method
    string statement;
    string[] argsNames;
    bool oneRowFlag;
}

Method[string] readMethods(immutable Answer answer)
{
    Method[string] methods;

    foreach(ref r; rangify(answer))
    {
        trace("found method row: ", r);

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

        try
        {
            m.name = r["method"].as!string;

            if(m.name.length == 0)
                throw new Exception("Method name is empty string", __FILE__, __LINE__);

            m.statement = r["sql_query"].as!string;

            {
                auto arr = r["args"].asArray;

                if(arr.dimsSize.length > 1)
                    throw new Exception("Array of args should be one dimensional", __FILE__, __LINE__);

                foreach(ref v; rangify(arr))
                    m.argsNames ~= v.as!string;
            }

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
