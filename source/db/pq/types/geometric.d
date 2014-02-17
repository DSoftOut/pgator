// Written in D programming language
/**
*   PostgreSQL geometric types binary format.
*
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module db.pq.types.geometric;

import db.pq.types.oids;
import std.numeric;
import std.conv;

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