// Written in D programming language
/**
*   PostgreSQL numeric format
*
*   Copyright: © 2014 DSoftOut
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
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
import std.range;
import core.memory;
import util;

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
    
    
	uint NUMERIC_FLAGBITS(Numeric n) 
	{
		return n.choice.n_header & NUMERIC_SIGN_MASK;
	}
	
	bool NUMERIC_IS_NAN(Numeric n)
	{
		return NUMERIC_FLAGBITS(n) == NUMERIC_NAN;
	}
	
	bool NUMERIC_IS_SHORT(Numeric n)
	{
		return NUMERIC_FLAGBITS(n) == NUMERIC_SHORT;
	}
    
    int NUMERIC_WEIGHT(Numeric n)
    {
    	return NUMERIC_IS_SHORT(n) ?
    		((n.choice.n_short.n_header & NUMERIC_SHORT_SIGN_MASK) ?
    		NUMERIC_NEG : NUMERIC_POS) : NUMERIC_FLAGBITS(n);
    }
    
    int NUMERIC_SIGN(Numeric n)
    {
    	return NUMERIC_IS_SHORT(n) ?
    		((n.choice.n_short.n_header & NUMERIC_SHORT_SIGN_MASK) ?
    		NUMERIC_NEG : NUMERIC_POS) : NUMERIC_FLAGBITS(n);
    }
    
    int NUMERIC_DSCALE(Numeric n)
    {
    	return NUMERIC_IS_SHORT(n) ? 
    		(n.choice.n_short.n_header & NUMERIC_SHORT_DSCALE_MASK) 
    			>> NUMERIC_SHORT_DSCALE_SHIFT 
			: (n.choice.n_long.n_sign_dscale & NUMERIC_DSCALE_MASK);
    }
    
    NumericDigit[] NUMERIC_DIGITS(Numeric num)
    {
    	return NUMERIC_IS_SHORT(num) ? 
    		num.choice.n_short.n_data : num.choice.n_long.n_data;
    }
    
    struct NumericVar
    {
    	int			weight;
    	int 		sign;
    	int			dscale;
    	NumericDigit[] buf;
    	NumericDigit[] digits;
    }
    
    void init_var_from_num(Numeric num, NumericVar* dest)
    {
    	dest.weight = NUMERIC_WEIGHT(num);
    	dest.sign   = NUMERIC_SIGN(num);
	    dest.dscale = NUMERIC_DSCALE(num);
	    dest.digits = NUMERIC_DIGITS(num);
    }
    
    string numeric_out(ref NumericVar num)
    {
    	string str;
    	
    	if(num.sign == NUMERIC_NAN)
    	{
    		return "NaN";
    	}
    	
    	str = get_str_from_var(num);
    	
    	return str;
    }
    
	/*
	 * get_str_from_var() -
	 *
	 *  Convert a var to text representation (guts of numeric_out).
	 *  The var is displayed to the number of digits indicated by its dscale.
	 *  Returns a palloc'd string.
	 */
	string get_str_from_var(ref NumericVar var)
	{
	    int         dscale;
	    char*       str;
	    char*       cp;
	    char*       endcp;
	    int         i;
	    int         d;
	    NumericDigit dig;
	
		static if(DEC_DIGITS > 1)
		{
			NumericDigit d1;
		}
	
	    dscale = var.dscale;
	
	    /*
	     * Allocate space for the result.
	     *
	     * i is set to the # of decimal digits before decimal point. dscale is the
	     * # of decimal digits we will print after decimal point. We may generate
	     * as many as DEC_DIGITS-1 excess digits at the end, and in addition we
	     * need room for sign, decimal point, null terminator.
	     */
	    i = (var.weight + 1) * DEC_DIGITS;
	    if (i <= 0)
	        i = 1;
	        
	    str = cast(char*)GC.malloc(i + dscale + DEC_DIGITS + 2);
	    cp = str;
	
	    /*
	     * Output a dash for negative values
	     */
	    if (var.sign == NUMERIC_NEG)
	        *cp++ = '-';
	
	    /*
	     * Output all digits before the decimal point
	     */
	    if (var.weight < 0)
	    {
	        d = var.weight + 1;
	        *cp++ = '0';
	    }
	    else
	    {
	        for (d = 0; d <= var.weight; d++)
	        {
	            dig = (d < var.digits.length) ? var.digits[d] : 0;
	            /* In the first digit, suppress extra leading decimal zeroes */
	            static if(DEC_DIGITS == 4)
	            {
	                bool putit = (d > 0);
	
	                d1 = dig / 1000;
	                dig -= d1 * 1000;
	                putit |= (d1 > 0);
	                if (putit)
	                    *cp++ = cast(char)(d1 + '0');
	                d1 = dig / 100;
	                dig -= d1 * 100;
	                putit |= (d1 > 0);
	                if (putit)
	                    *cp++ = cast(char)(d1 + '0');
	                d1 = dig / 10;
	                dig -= d1 * 10;
	                putit |= (d1 > 0);
	                if (putit)
	                    *cp++ = cast(char)(d1 + '0');
	                *cp++ = cast(char)(dig + '0');
	            }
	            else static if(DEC_DIGITS == 2)
	            {
		            d1 = dig / 10;
		            dig -= d1 * 10;
		            if (d1 > 0 || d > 0)
		                *cp++ = cast(char)(d1 + '0');
		            *cp++ = cast(char)(dig + '0');
	            }
	            else static if(DEC_DIGITS == 1)
	            {
	            	*cp++ = cast(char)(dig + '0');
	            }
	            else pragma(error, "unsupported NBASE");
	        }
	    }
	
	    /*
	     * If requested, output a decimal point and all the digits that follow it.
	     * We initially put out a multiple of DEC_DIGITS digits, then truncate if
	     * needed.
	     */
	    if (dscale > 0)
	    {
	        *cp++ = '.';
	        endcp = cp + dscale;
	        for (i = 0; i < dscale; d++, i += DEC_DIGITS)
	        {
	            dig = (d >= 0 && d < var.digits.length) ? var.digits[d] : 0;
	            static if(DEC_DIGITS == 4)
	            {
		            d1 = dig / 1000;
		            dig -= d1 * 1000;
		            *cp++ = cast(char)(d1 + '0');
		            d1 = dig / 100;
		            dig -= d1 * 100;
		            *cp++ = cast(char)(d1 + '0');
		            d1 = dig / 10;
		            dig -= d1 * 10;
		            *cp++ = cast(char)(d1 + '0');
		            *cp++ = cast(char)(dig + '0');
	            }
	            else static if(DEC_DIGITS == 2)
	            {
		            d1 = dig / 10;
		            dig -= d1 * 10;
		            *cp++ = cast(char)(d1 + '0');
		            *cp++ = cast(char)(dig + '0');
	            }
	            else static if(DEC_DIGITS == 1)
	            {
	            	*cp++ = cast(char)(dig + '0');
            	}
            	else pragma(error, "unsupported NBASE");
	        }
	        cp = endcp;
	    }
	
	    /*
	     * terminate the string and return it
	     */
	    *cp = '\0';
	    return str.fromStringz;
	}
}

alias ushort NumericDigit;
enum NBASE = 10000;
alias Numeric = NumericData*;

alias PGNumeric = string;

PGNumeric convert(PQType type)(ubyte[] val)
    if(type == PQType.Numeric)
{
	assert(val.length >= 4*ushort.sizeof);
	
	NumericVar	value;
	val.read!ushort; // num of digits
	value.weight = val.read!short;
	value.sign = val.read!ushort;
	value.dscale = val.read!ushort;
	
	auto len = val.length / NumericDigit.sizeof;
	value.digits = new NumericDigit[len];
	foreach(i; 0 .. len)
	{
		NumericDigit d = val.read!NumericDigit;
		value.digits[i] = d;
	}
	
	return numeric_out(value);
}

version(IntegrationTest2)
{
    import db.pool;
    import std.random;
    import std.range;
    import std.math;
    import vibe.data.bson;
    import derelict.pq.pq;
    import dlogg.log;
    import dlogg.buffered;
    
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
            } else
            {
                query = "SELECT "~val~"::NUMERIC as test_field";
            }

            logger.logInfo(query);
            auto res = Bson.fromJson(pool.execTransaction([query]).front.toJson);

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
        testValue(delayed, "0");
        testValue(delayed, "0.0146328");
        testValue(delayed, "42");
        testValue(delayed, "NaN");
        testValue(delayed, "0.0007");
        testValue(delayed, "0.007");
        testValue(delayed, "0.07");
        testValue(delayed, "0.7");
        testValue(delayed, "7");
        testValue(delayed, "70");
        testValue(delayed, "700");
        testValue(delayed, "7000");
        testValue(delayed, "70000");
        
        testValue(delayed, "7.0");
        testValue(delayed, "70.0");
        testValue(delayed, "700.0");
        testValue(delayed, "7000.0");
        testValue(delayed, "70000.000");
        
        testValue(delayed, "2354877787627192443");
        testValue(delayed, "2354877787627192443.0");
        testValue(delayed, "2354877787627192443.00000");
    }
}