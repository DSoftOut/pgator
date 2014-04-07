// Written in D programming language
/**
*   PostgreSQL geometric types binary format.
*
*   Copyright: © 2014 DSoftOut
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module pgator.db.pq.types.geometric;

import pgator.db.pq.types.oids;
import std.array;
import std.bitmanip;
import std.conv;
import std.math;

struct Point
{
    double x, y;
    
    string toString() const
    {
        return text("(",x,",",y,")");
    }
    
    bool opEquals(const Point b) const
    {
        return x.approxEqual(b.x) && y.approxEqual(b.y); 
    }
}

struct LineSegment
{
    double x1, y1, x2, y2;
    
    string toString() const
    {
        return text("((",x1,",",y1,"),","(",x2,",",y2,"))");
    }
    
    bool opEquals(const LineSegment b) const
    {
        return x1.approxEqual(b.x1) && y1.approxEqual(b.y1) &&
               x2.approxEqual(b.x2) && y2.approxEqual(b.y2); 
    }
}

struct Path
{
    bool closed;
    Point[] points;
    
    string toString() const
    {
        auto builder = appender!string;
        
        builder.put(closed ? '(' : '[');
        foreach(i,p; points)
        {
            builder.put(p.to!string);
            if(i != points.length -1) 
                builder.put(',');
        }
        builder.put(closed ? ')' : ']');
        return builder.data;
    }
}

struct Box
{
    double highx, highy, lowx, lowy;
    
    this(double ax, double ay, double bx, double by)
    {
        if(ax > bx)
        {
            highx = ax;
            lowx  = bx;
        }
        else
        {
            lowx  = ax;
            highx = bx;
        }
         
        if(ay > by)
        {
            highy = ay;
            lowy  = by;
        } else
        {
            lowy  = ay;
            highy = by;
        }
    }
    
    string toString() const
    {
        return text("((",highx,",",highy,"),","(",lowx,",",lowy,"))");
    }
    
    bool opEquals(const Box b) const
    {
        return highx.approxEqual(b.highx) && highy.approxEqual(b.highy) &&
               lowx.approxEqual(b.lowx) && lowy.approxEqual(b.lowy); 
    }
}

struct Polygon
{
    Point[] points;
    
    string toString() const
    {
        auto builder = appender!string;
        
        builder.put('(');
        foreach(i,p; points)
        {
            builder.put(p.to!string);
            if(i != points.length -1) 
                builder.put(',');
        }
        builder.put(')');
        return builder.data;
    }
}

struct Circle
{
    Point center;
    double radius;
    
    string toString() const
    {
        auto builder = appender!string;
        
        builder.put('<');
        builder.put(center.to!string);
        builder.put(',');
        builder.put(radius.to!string);
        builder.put('>');
        return builder.data;
    }
    
    bool opEquals(const Circle b) const
    {
        return center == b.center && radius.approxEqual(b.radius); 
    }   
}

Point convert(PQType type)(ubyte[] val)
    if(type == PQType.Point)
{
    assert(val.length == 16);
    return Point(val.read!double, val.read!double);
}

LineSegment convert(PQType type)(ubyte[] val)
    if(type == PQType.LineSegment)
{
    assert(val.length == double.sizeof*4);
    double x1 = val.read!double;
    double y1 = val.read!double;
    double x2 = val.read!double;
    double y2 = val.read!double;
    return LineSegment(x1, y1, x2, y2);
}

Path convert(PQType type)(ubyte[] val)
    if(type == PQType.Path)
{
    Path path;
    path.closed = val.read!bool;
    size_t l = cast(size_t)val.read!uint;
    path.points = new Point[l];
    
    assert(val.length == 2*double.sizeof*l);
    foreach(ref p; path.points)
    {
        p = Point(val.read!double, val.read!double);
    }
    return path;
}

Box convert(PQType type)(ubyte[] val)
    if(type == PQType.Box)
{
    assert(val.length == 4*double.sizeof);
    double highx = val.read!double;
    double highy = val.read!double;
    double lowx = val.read!double;
    double lowy = val.read!double;
    return Box(highx, highy, lowx, lowy);
}

Polygon convert(PQType type)(ubyte[] val)
    if(type == PQType.Polygon)
{
    Polygon poly;
    size_t l = val.read!uint;
    poly.points = new Point[l];
    
    assert(val.length == 2*double.sizeof*l);
    foreach(ref p; poly.points)
    {
        p = Point(val.read!double, val.read!double);
    }
    return poly;
}

Circle convert(PQType type)(ubyte[] val)
    if(type == PQType.Circle)
{
    assert(val.length == 3*double.sizeof);
    double centerx = val.read!double;
    double centery = val.read!double;
    double radius = val.read!double;

    return Circle(Point(centerx, centery), radius);
}

version(IntegrationTest2)
{
    import pgator.db.pq.types.test;
    import pgator.db.pool;
    import std.random;
    import std.algorithm;
    import dlogg.log;
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Point)
    {
        logger.logInfo("Testing Point...");
          
        foreach(i; 0..100)
        {
            auto test = Point(uniform(-100.0, 100.0), uniform(-100.0, 100.0));
            testValue!(Point, (v) => "'"~v.to!string~"'")(logger, pool, test, "point");
        }
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.LineSegment)
    {
        logger.logInfo("Testing LineSegment...");
          
        foreach(i; 0..100)
        {
            auto test = LineSegment(uniform(-100.0, 100.0), uniform(-100.0, 100.0),
                                    uniform(-100.0, 100.0), uniform(-100.0, 100.0));
            testValue!(LineSegment, (v) => "'"~v.to!string~"'")(logger, pool, test, "lseg");
        }
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Path)
    {
        logger.logInfo("Testing Path...");
          
        Path getRandPath()
        {
            Path path;
            path.closed = uniform!"[]"(0,1) != 0;
            
            auto builder = appender!(Point[]);
            foreach(i; 0..uniform(1,15))
            {
                builder.put(Point(uniform(-100.0, 100.0), uniform(-100.0, 100.0)));
            }
            path.points = builder.data;
            
            return path;
        }  
        foreach(i; 0..100)
        {
            testValue!(Path, (v) => "'"~v.to!string~"'")(logger, pool, getRandPath, "path");
        }
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Box)
    {
        logger.logInfo("Testing Box...");
          
        foreach(i; 0..100)
        {
            auto test = Box(uniform(-100.0, 100.0), uniform(-100.0, 100.0),
                            uniform(-100.0, 100.0), uniform(-100.0, 100.0));
            testValue!(Box, (v) => "'"~v.to!string~"'")(logger, pool, test, "box");
        }
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Polygon)
    {
        logger.logInfo("Testing Polygon...");
          
        Polygon getRandPoly()
        {
            Polygon poly;
            
            auto builder = appender!(Point[]);
            foreach(i; 0..uniform(1,15))
            {
                builder.put(Point(uniform(-100.0, 100.0), uniform(-100.0, 100.0)));
            }
            poly.points = builder.data;
            
            return poly;
        }  
        foreach(i; 0..100)
        {
            testValue!(Polygon, (v) => "'"~v.to!string~"'")(logger, pool, getRandPoly, "polygon");
        }
    }
    
    void test(PQType type)(shared ILogger logger, shared IConnectionPool pool)
        if(type == PQType.Circle)
    {
        logger.logInfo("Testing Circle...");
          
        foreach(i; 0..100)
        {
            auto test = Circle(Point(uniform(-100.0, 100.0), uniform(-100.0, 100.0)),
                            uniform(0, 100.0));
            testValue!(Circle, (v) => "'"~v.to!string~"'")(logger, pool, test, "circle");
        }
    }
}