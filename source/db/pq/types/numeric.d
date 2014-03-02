// Written in D programming language
/**
*   PostgreSQL numeric format
*
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module db.pq.types.numeric;

import db.pq.types.oids;
import std.bitmanip;
import std.algorithm;
import std.array;
import std.format;
import std.conv;
import std.exception;
import std.bigint;

private // inner representation
{
    /* From libpq docs
     * The Numeric type as stored on disk.
     *
     * If the high bits of the first word of a NumericChoice (n_header, or
     * n_short.n_header, or n_long.n_sign_dscale) are NUMERIC_SHORT, then the
     * numeric follows the NumericShort format; if they are NUMERIC_POS or
     * NUMERIC_NEG, it follows the NumericLong format.  If they are NUMERIC_NAN,
     * it is a NaN.  We currently always store a NaN using just two bytes (i.e.
     * only n_header), but previous releases used only the NumericLong format,
     * so we might find 4-byte NaNs on disk if a database has been migrated using
     * pg_upgrade.  In either case, when the high bits indicate a NaN, the
     * remaining bits are never examined.  Currently, we always initialize these
     * to zero, but it might be possible to use them for some other purpose in
     * the future.
     *
     * In the NumericShort format, the remaining 14 bits of the header word
     * (n_short.n_header) are allocated as follows: 1 for sign (positive or
     * negative), 6 for dynamic scale, and 7 for weight.  In practice, most
     * commonly-encountered values can be represented this way.
     *
     * In the NumericLong format, the remaining 14 bits of the header word
     * (n_long.n_sign_dscale) represent the display scale; and the weight is
     * stored separately in n_weight.
     *
     * NOTE: by convention, values in the packed form have been stripped of
     * all leading and trailing zero digits (where a "digit" is of base NBASE).
     * In particular, if the value is zero, there will be no digits at all!
     * The weight is arbitrary in that case, but we normally set it to zero.
     */

    enum HALF_NBASE = 5000;
    enum DEC_DIGITS = 4;
    
    struct NumericShort
    {
        ushort       n_header;       /* Sign + display scale + weight */
        NumericDigit n_data[];      /* Digits */
    };
    
    struct NumericLong
    {
        ushort      n_sign_dscale;  /* Sign + display scale */
        short       n_weight;       /* Weight of 1st digit  */
        NumericDigit n_data[];      /* Digits */
    };
    
    union NumericChoice
    {
        ushort      n_header;       /* Header word */
        NumericLong n_long;         /* Long form (4-byte header) */
        NumericShort n_short;       /* Short form (2-byte header) */
    };
    
    struct NumericData
    {
        int           vl_len_;        /* varlena header (do not touch directly!) */
        NumericChoice choice;         /* choice of format */
    };
    
    enum NUMERIC_SHORT_SIGN_MASK = 0x2000;
    enum NUMERIC_SHORT_DSCALE_MASK  = 0x1F80;
    enum NUMERIC_SHORT_DSCALE_SHIFT = 7;
    enum NUMERIC_SHORT_WEIGHT_SIGN_MASK = 0x0040;
    enum NUMERIC_SHORT_WEIGHT_MASK      = 0x003F;
    
    enum NUMERIC_DSCALE_MASK = 0x3FFF;
    
    enum NUMERIC_SIGN_MASK = 0xC000;
    enum NUMERIC_POS       = 0x0000;
    enum NUMERIC_NEG       = 0x4000;
    enum NUMERIC_SHORT     = 0x8000;
    enum NUMERIC_NAN       = 0xC000;
    
    auto NUMERIC_FLAGBITS(ushort n_header) 
    {
        return n_header & NUMERIC_SIGN_MASK;
    }
    
    bool NUMERIC_IS_NAN(ushort n)
    {
        return NUMERIC_FLAGBITS(n) == NUMERIC_NAN;
    }
    
    bool NUMERIC_IS_SHORT(ushort n)
    {
        return NUMERIC_FLAGBITS(n) == NUMERIC_SHORT;
    }
}

alias ushort NumericDigit;
enum NBASE      = 10000;

/**
*   Temporary structure to hold PostgreSQL arbitrary precision numbers.
*   
*   Warning: When the number can fit into double type, backend automatically
*       converting it to double while serializing into Bson/Json.  
*/    
struct Numeric
{
    BigInt mantis;
    size_t scale;
    bool isNan = true; // deafault is nan
    
    this(bool sign, NumericDigit[] digits)
    {
        auto builder = appender!string();
        
        foreach(i,dig; digits)
        {
            foreach_reverse(j; 0..DEC_DIGITS)
            {
                auto d = dig / (10 ^^ j);
                builder.put(d.to!string);
                dig -= d * (10 ^^ j);
            } 
        }

        // truncate besides zeros
        auto str = builder.data.strip('0');
        
        if(sign)
        	mantis = '-' ~ str;
        else
        	mantis = str;
    	
    	isNan = false;
    }
    
    this(NumericShort num)
    {
        bool sign  = (num.n_header & NUMERIC_SHORT_SIGN_MASK) != 0;
        scale = (num.n_header & NUMERIC_SHORT_DSCALE_MASK) >> NUMERIC_SHORT_DSCALE_SHIFT;

        this(sign, num.n_data);
    }
    
    this(NumericLong num)
    {
        bool sign  = NUMERIC_FLAGBITS(num.n_sign_dscale) != 0;
        // weight = n_header & NUMERIC_DSCALE_MASK; // weight and scale are swapped
        scale = num.n_weight;                       // don't know why
        
        this(sign, num.n_data);
    }
    
    
    /**
    *   If the numeric fits double boundaries, stores it 
    *   into $(B val) and returns true, else returns false
    *   and fills $(B val) with NaN.
    */
    bool canBeNative(out double val)
    {
        try
        {
            val = cast(double)this;
            auto orig = toString;
            
            auto builder = appender!string;
            formattedWrite(builder, "%."~orig.find('.').length.to!string~"f", val);
            enforce(builder.data.strip('0') == orig);
        } catch(Exception e)
        {
            val = double.nan;
            return false;
        }
        return true;
    }
    
    /**
    *   Transforming numeric into double.
    *   Dangerous, returns valid result when
    *	it can fit in double.
    *
    *	See_Also: canBeNative
    */
    T opCast(T)() if(is(T == double))
    {
        return toString.to!double;
    }
    
    /**
    *	Converting the numeric into string.
    */
    string toString()
    {
        if(isNan) return "nan";
        
        string str;
        mantis.toString((chars) {str = chars.idup;}, "d");

        // putting decimal point
        if(scale > 0)
        {
            if(str.length <= scale)
            {
                auto zbuilder = appender!string;
                zbuilder.put("0.");
                foreach(i; 0 .. scale - str.length)
                	zbuilder.put('0');
                str = zbuilder.data ~ str;    
            }
            else str = str[0 .. $-scale] ~ '.' ~ str[$-scale .. $];
        } 
        // returning sign in place
        if(mantis < 0) str = '-' ~ str;
        return str;
    }
}

Numeric convert(PQType type)(ubyte[] val)
    if(type == PQType.Numeric)
{   
    assert(val.length >= 2*ushort.sizeof);
    val.read!int; // varlena go away! i hate you!
    
    auto n_header = val.read!ushort;
    NumericData raw;
    raw.choice.n_header = n_header;
    assert(val.length % NumericDigit.sizeof == 0);
    
    if(NUMERIC_IS_SHORT(n_header))
    {
        while(val.length > 0)
            raw.choice.n_short.n_data ~= val.read!NumericDigit;
            
        return Numeric(raw.choice.n_short);
    } else if(!NUMERIC_IS_NAN(n_header))
    {
        raw.choice.n_long.n_weight = val.read!short;
        while(val.length > 0)
            raw.choice.n_long.n_data ~= val.read!NumericDigit;
            
        return Numeric(raw.choice.n_long);
    } else
    {
        return Numeric();
    }
}

version(IntegrationTest2)
{
    import db.pool;
    import std.random;
    import std.range;
    import std.math;
    import vibe.data.bson;
    import derelict.pq.pq;
    import log;
    import bufflog;
    
    void test(PQType type)(shared ILogger strictLogger, shared IConnectionPool pool)
        if(type == PQType.Numeric)
    {
		auto delayed = new shared BufferedLogger(strictLogger);
		scope(exit) delayed.finalize();
		scope(failure) delayed.minOutputLevel = LoggingLevel.Notice;
		
        void testValue(shared ILogger logger, string val)
        {
            string query;
            if(val == "NaN") 
            {
                query = "SELECT '"~val~"'::NUMERIC as test_field";
                val = "nan";
            } else
            {
                query = "SELECT "~val~"::NUMERIC as test_field";
            }

            logger.logInfo(query);
            auto res = cast()pool.execTransaction([query]).front;

            logger.logInfo(text(res));
            auto node = res.get!(Bson[string])["test_field"][0];
            if(node.type == Bson.Type.double_)
            {
                auto remote = node.get!double;
                auto local  = val.to!double;
                if(!isNaN(local))
                    assert(remote == local, remote.to!string ~ "!=" ~ val); 
                else
                    assert(isNaN(remote), remote.to!string ~ " is not NaN!");
            } else
            {
                auto retval = node.get!string;
                assert(retval == val, retval ~ "!=" ~ val); 
            }
        }
        
        string bigNumber(size_t size)
        {
            auto builder = appender!string;
            immutable digits = "0123456789";
            foreach(i; 0..size)
                builder.put(digits[uniform(0, digits.length)]);
            return builder.data.strip('0');    
        }
        
        strictLogger.logInfo("Testing Numeric...");
        foreach(i; 0..100)
        {
            testValue(delayed, (100*uniform(-1.0, 1.0)).to!string);
        }
        // big numbers
        foreach(i; 0..100)
        {
            testValue(delayed, bigNumber(100) ~ "." ~ bigNumber(100));
        }
        // special cases
        testValue(delayed, "0.0146328");
        testValue(delayed, "42");
        testValue(delayed, "NaN");
    }
}