// Written in D programming language
/**
*   PostgreSQL major types oids.
*
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module db.pq.types;

import derelict.pq.pq;
import vibe.data.json;
import vibe.data.bson;
import std.algorithm;
import std.traits;
import std.conv;
import std.numeric;
import std.typecons;
import std.datetime;
import std.format;
import std.range;
import std.socket;
import core.sys.posix.sys.socket;
import util;

enum PQType : Oid
{
    Bool = 16,
    ByteArray = 17,
    Char = 18,
    Name = 19,
    Int8 = 20,
    Int2 = 21,
    Int2Vector = 22,
    Int4 = 23,
    RegProc = 24,
    Text = 25,
    Oid = 26,
    Tid = 27,
    Xid = 28,
    Cid = 29,
    OidVec = 30,
    
    TypeCatalog = 71,
    AttributeCatalog = 75,
    ProcCatalog = 81,
    ClassCatalog = 83,
    
    Json = 114,
    Xml = 142,
    NodeTree = 194,
    StorageManager = 210,
    
    Point = 600,
    LineSegment = 601,
    Path = 602,
    Box = 603,
    Polygon = 604,
    Line = 628,
    
    Float4 = 700,
    Float8 = 701,
    AbsTime = 702,
    RelTime = 703,
    Interval = 704,
    Unknown = 705,
    
    Circle = 718,
    Money = 790,
    MacAddress = 829,
    HostAddress = 869,
    NetworkAddress = 650,
    
    Int2Array = 1005,
    Int4Array = 1007,
    TextArray = 1009,
    OidArray  = 1028,
    Float4Array = 1021,
    AccessControlList = 1033,
    CStringArray = 1263,
    
    FixedString = 1042,
    VariableString = 1043,
    
    Date = 1082,
    Time = 1083,
    TimeStamp = 1114,
    TimeStampWithZone = 1184,
    TimeInterval = 1186,
    TimeWithZone = 1266,
    
    FixedBitString = 1560,
    VariableBitString = 1562,
    
    Numeric = 1700,
    RefCursor = 1790,
    RegProcWithArgs = 2202,
    RegOperator = 2203,
    RegOperatorWithArgs = 2204,
    RegClass = 2205,
    RegType = 2206,
    RegTypeArray = 2211,
    
    UUID = 2950,
    TSVector = 3614,
    GTSVector = 3642,
    TSQuery = 3615,
    RegConfig = 3734,
    RegDictionary = 3769,
    
    Int4Range = 3904,
    NumRange = 3906,
    TimeStampRange = 3908,
    TimeStampWithZoneRange = 3910,
    DateRange = 3912,
    Int8Range = 3926,
    
    // Pseudo types
    Record = 2249,
    RecordArray = 2287,
    CString = 2275,
    AnyVoid = 2276,
    AnyArray = 2277,
    Void = 2278,
    Trigger = 2279,
    EventTrigger = 3838,
    LanguageHandler = 2280,
    Internal = 2281,
    Opaque = 2282,
    AnyElement = 2283,
    AnyNoArray = 2776,
    AnyEnum = 3500,
    FDWHandler = 3115,
    AnyRange = 3831
}

bool nonConvertable(PQType type)
{
    switch(type)
    {
        case PQType.TypeCatalog: return true;
        case PQType.AttributeCatalog: return true;
        case PQType.ProcCatalog: return true;
        case PQType.ClassCatalog: return true; 
        case PQType.StorageManager: return true;
        case PQType.Line: return true;
        
        // awaiting implementation
        case PQType.Int2Array: return true;
        case PQType.Int4Array: return true;
        case PQType.TextArray: return true;
        case PQType.OidArray: return true;
        case PQType.Float4Array: return true;
        case PQType.AccessControlList: return true;
        case PQType.CStringArray: return true;
        
        case PQType.FixedString: return true;
        case PQType.VariableString: return true;
        
        case PQType.Date: return true;
        case PQType.Time: return true;
        case PQType.TimeStamp: return true;
        case PQType.TimeStampWithZone: return true;
        case PQType.TimeInterval: return true;
        case PQType.TimeWithZone: return true;
        
        case PQType.FixedBitString: return true;
        case PQType.VariableBitString: return true;
        
        case PQType.Numeric: return true;
        case PQType.RefCursor: return true;
        case PQType.RegProcWithArgs: return true;
        case PQType.RegOperator: return true;
        case PQType.RegOperatorWithArgs: return true;
        case PQType.RegClass: return true;
        case PQType.RegType: return true;
        case PQType.RegTypeArray: return true;
        
        case PQType.UUID: return true;
        case PQType.TSVector: return true;
        case PQType.GTSVector: return true;
        case PQType.TSQuery: return true;
        case PQType.RegConfig: return true;
        case PQType.RegDictionary: return true;
        
        case PQType.Int4Range: return true;
        case PQType.NumRange: return true;
        case PQType.TimeStampRange: return true;
        case PQType.TimeStampWithZoneRange: return true;
        case PQType.DateRange: return true;
        case PQType.Int8Range: return true;
        
        // Pseudo types
        case PQType.Record: return true;
        case PQType.RecordArray: return true;
        case PQType.CString: return true;
        case PQType.AnyVoid: return true;
        case PQType.AnyArray: return true;
        case PQType.Void: return true;
        case PQType.Trigger: return true;
        case PQType.EventTrigger: return true;
        case PQType.LanguageHandler: return true;
        case PQType.Internal: return true;
        case PQType.Opaque: return true;
        case PQType.AnyElement: return true;
        case PQType.AnyNoArray: return true;
        case PQType.AnyEnum: return true;
        case PQType.FDWHandler: return true;
        case PQType.AnyRange: return true;
        default: return false;
    }
}

Bson toBson(PQType type)(ubyte[] val)
{
    template IsNativeSupport(T)
    {  
        static if (is(T == string) || is(T == ubyte[]) || is(T == Json))
        {
            enum IsNativeSupport = true;
        }
        else static if(isArray!T)
        {
            enum IsNativeSupport = IsNativeSupport!(ElementType!T);
        }
        else
        {
            enum IsNativeSupport = 
                   is(T == bool)
                || is(T == float)
                || is(T == double)
                || is(T == short)
                || is(T == ushort)
                || is(T == int)
                || is(T == uint)
                || is(T == long)
                || is(T == ulong);
        }
    }
    
    auto convVal = convert!type(val);
    alias typeof(convVal) T;
    static if(IsNativeSupport!T)
    {
        return serializeToBson(convVal); 
    } 
    else static if(is(T == SysTime))
    {
        return serializeToBson(convVal.stdTime);
    } 
    else static if(is(T == struct))
    {
        return serializeToBson(convVal);
    }
    else
    {
        return serializeToBson(convVal.to!string);   
    }
}

Bson pqToBson(PQType type, ubyte[] val)
{
    foreach(ts; __traits(allMembers, PQType))
    {
        enum t = mixin("PQType."~ts);
        static if(nonConvertable(t))
        {
            enum errMsg = ts ~ " is not supported!";
            pragma(msg, errMsg);
            assert(false,errMsg);
        } else
        {
            if(type == t)
                return toBson!t(val);
        }
    }
    assert(false, "Unknown type "~to!string(type)~"!");
}

// ======================= Types ===========================
alias ushort RegProc;
alias ushort Oid;
alias uint Xid;
alias uint Cid;

struct PQTid
{
    uint blockId, blockNumber;
}

struct Point
{
    float x, y;
}

struct LineSegment
{
    float x1, y1, x2, y2;
}

struct Path
{
    bool closed;
    Point[] points;
}

struct Box
{
    float highx, highy, lowx, lowy;
}

struct Polygon
{
    Point[] points;
}

struct Circle
{
    Point center;
    float radius;
}

struct Interval
{
    uint status;
    SysTime[2] data;
}

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

//================= Binary converting funcs =================
bool convert(PQType type)(ubyte[] val)
    if(type == PQType.Bool)
{
    assert(val.length == 1);
    return val[0] != 0;
}

string convert(PQType type)(ubyte[] val)
    if(type == PQType.ByteArray)
{
    return cast(string)val.dup;
}

char convert(PQType type)(ubyte[] val)
    if(type == PQType.Char)
{
    assert(val.length == 1);
    return cast(char)val[0];
}

string convert(PQType type)(ubyte[] val)
    if(type == PQType.Name)
{
    assert(val.length == 64);
    return cast(string)val.dup;
}

long convert(PQType type)(ubyte[] val)
    if(type == PQType.Int8)
{
    assert(val.length == 8);
    return (cast(long[])val)[0];
}

short convert(PQType type)(ubyte[] val)
    if(type == PQType.Int2)
{
    assert(val.length == 2);
    return (cast(short[])val)[0];
}

short[] convert(PQType type)(ubyte[] val)
    if(type == PQType.Int2Vector)
{
    assert(val.length % 2 == 0);
    return (cast(short[])val).dup;
}

int convert(PQType type)(ubyte[] val)
    if(type == PQType.Int4)
{
    assert(val.length == 4);
    return (cast(int[])val)[0];
}

RegProc convert(PQType type)(ubyte[] val)
    if(type == PQType.RegProc)
{
    assert(val.length == 4);
    return (cast(ushort[])val)[0];
}

string convert(PQType type)(ubyte[] val)
    if(type == PQType.Text)
{
    assert(val.length > 0);
    return fromStringz(cast(char*)val.ptr);
}

Oid convert(PQType type)(ubyte[] val)
    if(type == PQType.Oid)
{
    assert(val.length == 2);
    return (cast(ushort[])val)[0];
}

PQTid convert(PQType type)(ubyte[] val)
    if(type == PQType.Tid)
{
    assert(val.length == 8);
    PQTid res;
    res.blockId = (cast(uint[])val)[0];
    res.blockNumber = (cast(uint[])val)[1];
    return res;
}

Xid convert(PQType type)(ubyte[] val)
    if(type == PQType.Xid)
{
    assert(val.length == 4);
    return (cast(uint[])val)[0];
}

Cid convert(PQType type)(ubyte[] val)
    if(type == PQType.Cid)
{
    assert(val.length == 4);
    return (cast(uint[])val)[0];
}

Oid[] convert(PQType type)(ubyte[] val)
    if(type == PQType.OidVec)
{
    assert(val.length % 2);
    return (cast(ushort[])val).dup;
}

Json convert(PQType type)(ubyte[] val)
    if(type == PQType.Json)
{
    string payload = fromStringz(cast(char*)val.ptr);
    return parseJsonString(payload);
}

string convert(PQType type)(ubyte[] val)
    if(type == PQType.Xml)
{
    assert(val.length > 0);
    return fromStringz(cast(char*)val.ptr);
}

string convert(PQType type)(ubyte[] val)
    if(type == PQType.NodeTree)
{
    assert(val.length > 0);
    return fromStringz(cast(char*)val.ptr);
}

Point convert(PQType type)(ubyte[] val)
    if(type == PQType.Point)
{
    assert(val.length == 2);
    static assert((CustomFloat!8).sizeof == 1);
    CustomFloat!8 a = (cast(CustomFloat!8[])val)[0];
    CustomFloat!8 b = (cast(CustomFloat!8[])val)[1];
    return Point(cast(float)a, cast(float)b);
}

LineSegment convert(PQType type)(ubyte[] val)
    if(type == PQType.LineSegment)
{
    assert(val.length == 4);
    static assert((CustomFloat!8).sizeof == 1);
    CustomFloat!8 x1 = (cast(CustomFloat!8[])val)[0];
    CustomFloat!8 y1 = (cast(CustomFloat!8[])val)[1];
    CustomFloat!8 x2 = (cast(CustomFloat!8[])val)[2];
    CustomFloat!8 y2 = (cast(CustomFloat!8[])val)[3];
    return LineSegment(cast(float)x1, cast(float)y1, cast(float)x2, cast(float)y2);
}

Path convert(PQType type)(ubyte[] val)
    if(type == PQType.Path)
{
    static assert((CustomFloat!8).sizeof == 1);
    
    Path path;
    path.closed = to!bool(val[0]); val = val[1..$];
    uint l = (cast(uint[])val[0..4])[0]; val = val[4..$];
    path.points = new Point[l];
    
    assert(val.length == 2*l);
    foreach(ref p; path.points)
    {
        CustomFloat!8 a = (cast(CustomFloat!8[])val)[0];
        CustomFloat!8 b = (cast(CustomFloat!8[])val)[1];
        p = Point(cast(float)a, cast(float)b);
        if(val.length > 2) val = val[2..$];
    }
    return path;
}

Box convert(PQType type)(ubyte[] val)
    if(type == PQType.Box)
{
    assert(val.length == 4);
    static assert((CustomFloat!8).sizeof == 1);
    CustomFloat!8 highx = (cast(CustomFloat!8[])val)[0];
    CustomFloat!8 highy = (cast(CustomFloat!8[])val)[1];
    CustomFloat!8 lowx = (cast(CustomFloat!8[])val)[2];
    CustomFloat!8 lowy = (cast(CustomFloat!8[])val)[3];
    return Box(cast(float)highx, cast(float)highy, cast(float)lowx, cast(float)lowy);
}

Polygon convert(PQType type)(ubyte[] val)
    if(type == PQType.Polygon)
{
    static assert((CustomFloat!8).sizeof == 1);
    
    Polygon poly;
    uint l = (cast(uint[])val[0..4])[0]; val = val[4..$];
    poly.points = new Point[l];
    
    assert(val.length == 2*l);
    foreach(ref p; poly.points)
    {
        CustomFloat!8 a = (cast(CustomFloat!8[])val)[0];
        CustomFloat!8 b = (cast(CustomFloat!8[])val)[1];
        p = Point(cast(float)a, cast(float)b);
        if(val.length > 2) val = val[2..$];
    }
    return poly;
}

float convert(PQType type)(ubyte[] val)
    if(type == PQType.Float4)
{
    assert(val.length == 1);
    static assert((CustomFloat!8).sizeof == 1);
    CustomFloat!8 v = (cast(CustomFloat!8[])val)[0];
    return cast(float)v;
}

float convert(PQType type)(ubyte[] val)
    if(type == PQType.Float8)
{
    assert(val.length == 1);
    return (cast(float[])val)[0];
}

SysTime convert(PQType type)(ubyte[] val)
    if(type == PQType.AbsTime)
{
    assert(val.length == 4);
    return SysTime(cast(long)(cast(uint[])val)[0]);
}

SysTime convert(PQType type)(ubyte[] val)
    if(type == PQType.RelTime)
{
    assert(val.length == 4);
    return SysTime(cast(long)(cast(uint[])val)[0]);
}

Interval convert(PQType type)(ubyte[] val)
    if(type == PQType.Interval)
{
    assert(val.length == 12);
    Interval interval;
    interval.status = (cast(uint[])val)[0];
    interval.data[0] = SysTime((cast(uint[])val)[1]);
    interval.data[1] = SysTime((cast(uint[])val)[2]);
    return interval;
}

string convert(PQType type)(ubyte[] val)
    if(type == PQType.Unknown)
{
    return convert!(PQType.Text)(val);
}

Circle convert(PQType type)(ubyte[] val)
    if(type == PQType.Circle)
{
    assert(val.length == 3);
    static assert((CustomFloat!8).sizeof == 1);
    CustomFloat!8 centerx = (cast(CustomFloat!8[])val)[0];
    CustomFloat!8 centery = (cast(CustomFloat!8[])val)[1];
    CustomFloat!8 radius = (cast(CustomFloat!8[])val)[2];

    return Circle(Point(cast(float)centerx, cast(float)centery), cast(float)radius);
}

long convert(PQType type)(ubyte[] val)
    if(type == PQType.Money)
{
    assert(val.length == 8);
    return (cast(long[])val)[0];
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
    ubyte family = val[0];
    ubyte bits = val[1];
    ubyte nb = val[3];
    assert(nb <= 16);
    val = val[4..$];
    assert(val.length == nb);
    ubyte[16] addrBytes;
    addrBytes[0..cast(size_t)nb] = val[0..cast(size_t)nb];  
    return PQInetAddress(addrBytes, bits, cast(PQInetAddress.Family)family);
}