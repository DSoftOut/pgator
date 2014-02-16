// Written in D programming language
/**
*   PostgreSQL major types oids.
*
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module db.pq.types;

import derelict.pq.pq;

enum PQType : Oid
{
    Bool = 16,
    ByteArray = 17,
    Char = 18,
    Name = 19,
    Int80 = 20,
    Int20 = 21,
    Int2Vector = 22,
    Int40 = 23,
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