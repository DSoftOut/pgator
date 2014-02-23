// Written in D programming language
/**
*   PostgreSQL network types binary format.
*
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
import core.sys.posix.sys.socket;

struct MacAddress
{
    ubyte a,b,c,d,e,f;
    
    this(ubyte a, ubyte b, ubyte c, ubyte d, ubyte e, ubyte f)
    {
        this.a = a;
        this.b = b;
        this.c = c;
        this.d = d;
        this.e = e;
        this.f = f;
    }
    
    this(ubyte[6] data)
    {
        a = data[0];
        b = data[1];
        c = data[2];
        d = data[3];
        e = data[4];
        f = data[5];
    } 
    
    this(string s)
    {
        auto data = s.splitter(':').array;
        enforce(data.length == 6, "Failed to parse MacAddress");
        ubyte[6] ret;
        foreach(i, bs; data)
        {
            enforce(bs.length == 2, "Failed to parse MacAddress");
            ret[i] = to!ubyte(bs);
        }
        this(ret);
    }
    
    string toString() const
    {
        string hex(const ubyte f)
        {
            auto builder = appender!string;
            formattedWrite(builder, "%x", f);
            return builder.data;
        }
        return text(hex(a),":",hex(b),":",hex(c),":",hex(d),":",hex(e),":",hex(f));
    }
}

struct PQInetAddress
{
    enum Family : ubyte
    {
        AFInet = AF_INET,
        AFInet6 = AF_INET+1,
    }
    Family family;
    ubyte bits;
    ubyte[16] ipaddr;
    
    this(string addr, ubyte maskBits)
    {
        bits = maskBits;
        auto ipv6sep = addr.find(':');
        if(ipv6sep.empty)
        {
            family = Family.AFInet;
            uint val = InternetAddress.parse(addr.dup);
            ipaddr[0..4] = (cast(ubyte[])[val])[];
        } else
        {
            family = Family.AFInet6;
            ipaddr = Internet6Address.parse(addr.dup);
        }
    }
    
    this(ubyte[16] adrr, ubyte maskBits, Family family)
    {
        this.family = family;
        bits = maskBits;
        ipaddr = adrr;
    }
    
    string toString()
    {
        if (family == Family.AFInet)
        {
            return InternetAddress.addrToString((cast(uint[])ipaddr)[0]);
        } else
        {
            return new Internet6Address(ipaddr, Internet6Address.PORT_ANY).toAddrString;
        }
    }
    
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
}

MacAddress convert(PQType type)(ubyte[] val)
    if(type == PQType.MacAddress)
{
    assert(val.length == 6);
    ubyte[6] buff;
    buff[] = val[0..6];
    return MacAddress(buff);
}

PQInetAddress convert(PQType type)(ubyte[] val)
    if((type == PQType.HostAddress || type == PQType.NetworkAddress))
{
    assert(val.length >= 4);
    ubyte family = val.read!ubyte;
    ubyte bits = val.read!ubyte;
    ubyte nb = val.read!ubyte;
    assert(nb <= 16);
    assert(val.length == nb);
    ubyte[16] addrBytes;
    addrBytes[0..cast(size_t)nb] = val[0..cast(size_t)nb];  
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
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.MacAddress)
    {
        logger.logInfo("================ MacAddress ======================");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.HostAddress)
    {
        logger.logInfo("================ HostAddress ======================");
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.NetworkAddress)
    {
        logger.logInfo("================ NetworkAddress ======================");
    }
}