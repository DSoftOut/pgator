// Written in D programming language
/**
*   PostgreSQL network types binary format.
*
*   Copyright: © 2014 DSoftOut
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module db.pq.types.inet;

import db.pq.types.oids;
import std.algorithm;
import std.array;
import std.bitmanip;
import std.socket;
import std.conv;
import std.format;
import vibe.data.bson;
import core.sys.posix.sys.socket;
import hexconv;

/**
*   MAC address. Struct holds 6 octets of the address.
*
*   Serializes to bson as string like 'xx:xx:xx:xx:xx:xx'
*/
struct PQMacAddress
{
    ubyte a,b,c,d,e,f;
    
    /**
    *   Creating from already separated octets
    */
    this(ubyte a, ubyte b, ubyte c, ubyte d, ubyte e, ubyte f)
    {
        this.a = a;
        this.b = b;
        this.c = c;
        this.d = d;
        this.e = e;
        this.f = f;
    }
    
    /**
    *   Creating form raw buffer
    */
    this(ubyte[6] data)
    {
        a = data[0];
        b = data[1];
        c = data[2];
        d = data[3];
        e = data[4];
        f = data[5];
    } 
    
    /**
    *   Parsing from string 'xx:xx:xx:xx:xx:xx'
    */
    this(string s)
    {
        auto data = s.splitter(':').array;
        enforce(data.length == 6, "Failed to parse MacAddress");
        ubyte[6] ret;
        foreach(i, bs; data)
        {
            enforce(bs.length == 2, "Failed to parse MacAddress");
            ret[i] = cast(ubyte)xtoul(bs);
        }
        this(ret);
    }
    
    /**
    *   Converting to string 'xx:xx:xx:xx:xx:xx'
    */
    string toString() const
    {
        string hex(const ubyte f)
        {
            auto builder = appender!string;
            formattedWrite(builder, "%02x", f);
            return builder.data;
        }
        return text(hex(a),":",hex(b),":",hex(c),":",hex(d),":",hex(e),":",hex(f));
    }
    
    /**
    *   Serializing to bson as string 'xx:xx:xx:xx:xx:xx'
    */
    Bson toBson() const
    {
        return Bson(toString);
    }
    
    /**
    *   Deserializing from bson. Expecting string format
    */
    static PQMacAddress fromBson(Bson bson)
    {
        return PQMacAddress(bson.get!string);
    }
}

/**
*   Struct holds PostgreSQL 'cidr' and 'inet' data types.
*   Supports IPv4 and IPv6 with explicit mask designation (CIDR model).
*/
struct PQInetAddress
{
	version(Windows)
	{
		import std.socket:AddressFamily;
		
		enum Family:int
		{
			AFInet = AddressFamily.INET,
			
			AFInet6 = AddressFamily.INET6
		}
	}
	else version(Posix)
	{
	    enum Family : ubyte
	    {
	        AFInet = AF_INET,
	        AFInet6 = AF_INET+1,
	    }
    }
	
	/// Address version
    Family family;
    /// Mask bits
    ubyte bits;
    /// Address body, not all buffer is used for IPv4
    ubyte[16] ipaddr;
    
    /**
    *   Parsing from string and network mask bits.
    */
    this(string addr, ubyte maskBits)
    {
        bits = maskBits;
        auto ipv6sep = addr.find(':');
        if(ipv6sep.empty)
        {
            family = Family.AFInet;
            uint val = InternetAddress.parse(addr.dup);
            (cast(ubyte[])ipaddr).write(val, 0);
        } else
        {
            family = Family.AFInet6;
            ipaddr = Internet6Address.parse(addr.dup);
        }
    }
    
    /**
    *   Creating from raw data
    */
    this(ubyte[16] adrr, ubyte maskBits, Family family)
    {
        this.family = family;
        bits = maskBits;
        ipaddr = adrr.dup;
    }
    
    /**
    *   Returns address without mask
    */
    string address() const @property
    {
        if (family == Family.AFInet)
        {
            return InternetAddress.addrToString((cast(ubyte[])ipaddr).peek!uint);
        } else
        {
            return new Internet6Address(ipaddr, Internet6Address.PORT_ANY).toAddrString;
        }
    }
    
    /**
    *   Converts to string like 'address/mast'
    */
    string toString()
    {
        if(bits != 0)
        {
            return address ~ "/" ~ bits.to!string;
        } else
        {
            return address;
        }
    }
    
    /**
    *   Casting to native D type, but mask is thrown away.
    */
    T opCast(T)() if(is(T==Address))
    {
        if (family == Family.AFInet)
        {
            return new InternetAddress((cast(uint[])ipaddr)[0], InternetAddress.PORT_ANY);
        } else
        {
            return new Internet6Address(ipaddr, Internet6Address.PORT_ANY);
        }
    }
    
    /**
    *   Serializing to BSON. Address and mask are holded separatly.
    *   Example:
    *   -------
    *   {
    *       "address": "address without mask",
    *       "mask": "bits count"
    *   }
    *   -------
    */
    Bson toBson() const
    {
        Bson[string] map;
        map["address"] = Bson(address);
        map["mask"] = Bson(cast(int)bits);
        return Bson(map);
    }
    
    /**
    *   Deserializing from BSON.
    */
    static PQInetAddress fromBson(Bson bson)
    {
        return PQInetAddress(bson.address.get!string, cast(ubyte)bson.mask.get!int);
    }
}

PQMacAddress convert(PQType type)(ubyte[] val)
    if(type == PQType.MacAddress)
{
    assert(val.length == 6);
    ubyte[6] buff;
    buff[] = val[0..6];
    return PQMacAddress(buff);
}

PQInetAddress convert(PQType type)(ubyte[] val)
    if((type == PQType.HostAddress || type == PQType.NetworkAddress))
{
    assert(val.length >= 4);
    ubyte family = val.read!ubyte;
    ubyte bits = val.read!ubyte;

    val.read!ubyte; // flag for cidr or inet recognize
    ubyte n = val.read!ubyte;
    ubyte[16] addrBytes;
    if(n == 4)
    {
        assert(val.length == 4, text("Expected 4 bytes, but got ", val.length));
        addrBytes[0..4] = val[0..4]; 
    } else if(n == 16)
    {
        assert(val.length == 16, text("Expected 16 bytes, but got ", val.length));
        addrBytes[] = val[0..16]; 
    } else
    {
        assert(false, text("Got invalid address size: ", n));
    }

    return PQInetAddress(addrBytes, bits, cast(PQInetAddress.Family)family);
}

version(IntegrationTest2)
{
    import db.pq.types.test;
    import db.pool;
    import std.random;
    import std.algorithm;
    import std.encoding;
    import std.math;
    import log;
    import bufflog;
    
    void test(PQType type)(shared ILogger strictLogger, shared IConnectionPool pool)
        if(type == PQType.MacAddress)
    {
        strictLogger.logInfo("Testing MacAddress...");

        auto logger = new shared BufferedLogger(strictLogger);
        scope(failure) logger.minOutputLevel = LoggingLevel.Notice;
        scope(exit) logger.finalize;
        
        assert(queryValue(logger, pool, "'08:00:2b:01:02:03'::macaddr").deserializeBson!PQMacAddress == PQMacAddress("08:00:2b:01:02:03"));
        assert(queryValue(logger, pool, "'08-00-2b-01-02-03'::macaddr").deserializeBson!PQMacAddress == PQMacAddress("08:00:2b:01:02:03"));
        assert(queryValue(logger, pool, "'08002b:010203'::macaddr").deserializeBson!PQMacAddress == PQMacAddress("08:00:2b:01:02:03"));
        assert(queryValue(logger, pool, "'08002b-010203'::macaddr").deserializeBson!PQMacAddress == PQMacAddress("08:00:2b:01:02:03"));
        assert(queryValue(logger, pool, "'0800.2b01.0203'::macaddr").deserializeBson!PQMacAddress == PQMacAddress("08:00:2b:01:02:03"));
        assert(queryValue(logger, pool, "'08002b010203'::macaddr").deserializeBson!PQMacAddress == PQMacAddress("08:00:2b:01:02:03"));
    }
    
    void test(PQType type)(shared ILogger strictLogger, shared IConnectionPool pool)
        if(type == PQType.HostAddress)
    {
        strictLogger.logInfo("Testing HostAddress...");

        auto logger = new shared BufferedLogger(strictLogger);
        scope(failure) logger.minOutputLevel = LoggingLevel.Notice;
        scope(exit) logger.finalize;
        
        assert(queryValue(logger, pool, "'192.168.100.128/25'::inet").deserializeBson!PQInetAddress == PQInetAddress("192.168.100.128", 25));
        assert(queryValue(logger, pool, "'10.1.2.3/32'::inet").deserializeBson!PQInetAddress == PQInetAddress("10.1.2.3", 32));
        assert(queryValue(logger, pool, "'2001:4f8:3:ba::/64'::inet").deserializeBson!PQInetAddress == PQInetAddress("2001:4f8:3:ba::", 64));
        assert(queryValue(logger, pool, "'2001:4f8:3:ba:2e0:81ff:fe22:d1f1/128'::inet").deserializeBson!PQInetAddress == PQInetAddress("2001:4f8:3:ba:2e0:81ff:fe22:d1f1", 128));
        assert(queryValue(logger, pool, "'::ffff:1.2.3.0/120'::inet").deserializeBson!PQInetAddress == PQInetAddress("::ffff:1.2.3.0", 120));
        assert(queryValue(logger, pool, "'::ffff:1.2.3.0/128'::inet").deserializeBson!PQInetAddress == PQInetAddress("::ffff:1.2.3.0", 128));
    }
    
    void test(PQType type)(shared ILogger strictLogger, shared IConnectionPool pool)
        if(type == PQType.NetworkAddress)
    {
        strictLogger.logInfo("Testing NetworkAddress...");

        auto logger = new shared BufferedLogger(strictLogger);
        scope(failure) logger.minOutputLevel = LoggingLevel.Notice;
        scope(exit) logger.finalize;

        assert(queryValue(logger, pool, "'192.168.100.128/25'::cidr").deserializeBson!PQInetAddress == PQInetAddress("192.168.100.128", 25));
        assert(queryValue(logger, pool, "'192.168/24'::cidr").deserializeBson!PQInetAddress == PQInetAddress("192.168.0.0", 24));
        assert(queryValue(logger, pool, "'192.168/25'::cidr").deserializeBson!PQInetAddress == PQInetAddress("192.168.0.0", 25));
        assert(queryValue(logger, pool, "'192.168.1'::cidr").deserializeBson!PQInetAddress == PQInetAddress("192.168.1.0", 24));
        assert(queryValue(logger, pool, "'192.168'::cidr").deserializeBson!PQInetAddress == PQInetAddress("192.168.0.0", 24));
        assert(queryValue(logger, pool, "'128.1'::cidr").deserializeBson!PQInetAddress == PQInetAddress("128.1.0.0", 16));
        assert(queryValue(logger, pool, "'128'::cidr").deserializeBson!PQInetAddress == PQInetAddress("128.0.0.0", 16));
        assert(queryValue(logger, pool, "'128.1.2'::cidr").deserializeBson!PQInetAddress == PQInetAddress("128.1.2.0", 24));
        assert(queryValue(logger, pool, "'10.1.2'::cidr").deserializeBson!PQInetAddress == PQInetAddress("10.1.2.0", 24));
        assert(queryValue(logger, pool, "'10.1'::cidr").deserializeBson!PQInetAddress == PQInetAddress("10.1.0.0", 16));
        assert(queryValue(logger, pool, "'10'::cidr").deserializeBson!PQInetAddress == PQInetAddress("10.0.0.0", 8));
        assert(queryValue(logger, pool, "'10.1.2.3/32'::cidr").deserializeBson!PQInetAddress == PQInetAddress("10.1.2.3", 32));
        assert(queryValue(logger, pool, "'2001:4f8:3:ba::/64'::cidr").deserializeBson!PQInetAddress == PQInetAddress("2001:4f8:3:ba::", 64));
        assert(queryValue(logger, pool, "'2001:4f8:3:ba:2e0:81ff:fe22:d1f1/128'::cidr").deserializeBson!PQInetAddress == PQInetAddress("2001:4f8:3:ba:2e0:81ff:fe22:d1f1", 128));
        assert(queryValue(logger, pool, "'::ffff:1.2.3.0/120'::cidr").deserializeBson!PQInetAddress == PQInetAddress("::ffff:1.2.3.0", 120));
        assert(queryValue(logger, pool, "'::ffff:1.2.3.0/128'::cidr").deserializeBson!PQInetAddress == PQInetAddress("::ffff:1.2.3.0", 128));
    }
}