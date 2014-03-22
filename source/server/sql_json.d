// Written in D programming language
/**
* This module contain json<->sql table from db.<br>
*
* Loads on SIGHUP or on startup
*
* Copyright: © 2014 DSoftOut
* License: Subject to the terms of the MIT license, as written in the included LICENSE file.
* Authors: Zaramzan <shamyan.roman@gmail.com>
*
*/
module server.sql_json;

import std.algorithm;
import std.traits;

import util;

/**
* Represent sql to json table line from database
*
* Authors: Zaramzan <shamyan.roman@gmail.com>
*/
struct Entry
{
	@required
	string method;
	
	@required
	string[] sql_queries;
	
	@required
	uint[] arg_nums;
	
	@required
	bool set_username;
	
	@required
	bool need_cache;
	
	@required
	bool read_only;
	
	@possible
	string[] reset_caches;
	
	@possible
	string[] reset_by;
	
	@possible
	string commentary;
	
	const bool isValidParams(in string[] params, out size_t expected)
	{
	    expected = arg_nums.reduce!"a+b";
		return params.length == expected;
	}
	
	const shared(Entry) toShared() @property
	{
		auto res = this;
		
		return cast(shared Entry) res;
	}
}

/**
* Contains methods descriptions, cache rules, etc
* 
* Authors: Zaramzan <shamyan.roman@gmail.com>
*/
shared class SqlJsonTable
{
	private Entry[string] map;
	
	/// Add entry to memory
	void add(in Entry entry)
	{
		map[entry.method] = entry.toShared();
	}
	
	void reset()
	{
		synchronized(this)
		{
			foreach(key; map.byKey())
			{
				map.remove(key);
			}
		}
	}
	
	/**
	* Returns: need_cache flag by method
	*/
	bool need_cache(string method)
	{
		auto p = method in map;
		
		if (p is null) return false;
		
		auto val = *p;
		
		return val.need_cache && val.read_only;
	}
	
	/**
	* Returns read_only flag by method
	*/
	bool read_only(string method)
	{
		auto p = method in map;
		
		if (p is null) return false;
		
		auto val = *p;
		
		return val.read_only;
	}
	
	/**
	* Returns: reset_caches array by method
	*/
	string[] reset_caches(string method)
	{
		auto p = method in map;
		
		if (p is null) return null;
		
		auto val = *p;
		
		return cast(string[])(val.reset_caches);
	}
	
	/**
	* Returns: reset_by array by method
	*/
	string[] reset_by(string method)
	{
		auto p = method in map;
		
		if (p is null) return null;
		
		auto val = *p;
		
		return cast(string[])(val.reset_by);
	}
	
	/**
	* Returns: array of needed drop methods by this method
	*/
	string[] needDrop(string method)
	{
		auto p = method in dropMap;
		
		if (p is null) return null;
		
		return cast(string[]) *p;
	}
	
	/**
	* Returns: true if method found, and put entry
	*/
	bool methodFound(string method, out Entry entry)
	{	
		shared Entry* p;
		
		p = method in map;
		
		if (p)
		{
			entry = cast(Entry) *p;
			
			return true;
		}
		
		return false;
	}
	
	/**
	* Returns entry by method
	*/
	Entry getEntry(string method)
	{
		auto p = method in map;
		
		if (p is null) return Entry();
		
		return cast(Entry) *p;
	}
	
	/**
	* Returns: true if method found
	*/
	bool methodFound(string method)
	{	
		return (method in map) !is null;
	}
	
	/// Make drop map
	void makeDropMap()
	{
		foreach(val; map.byValue())
		{
			shared string[] arr = new shared string[0];
			
			if (val.need_cache)
			{
				if (!val.read_only)
				{
					foreach(str1; val.reset_caches)
					{
						foreach(key; map.byKey())
						{
							foreach(str2; map[key].reset_by)
							{
								if (str1 == str2) 
								{
									arr ~= key; //key is method
									break;
								}
							} 
						}
					}
				}
			}
			
			dropMap[val.method] = arr.dup;
		}
		
		dropMap.rehash();
	}
	
	private:
	
	alias string[] dropArr;
	
	dropArr[string] dropMap;
	
}




version(unittest)
{
	shared SqlJsonTable table;
	
	void initTable()
	{
		table = new shared SqlJsonTable();
		
		auto entry1 = Entry();
		entry1.method = "subtract";
		entry1.arg_nums = [2];
		entry1.need_cache = true;
		entry1.reset_caches = ["drop", "safe", "pure"];
		entry1.reset_by = ["drop", "unsafe"];
		
		auto entry2 = Entry();
		entry2.method = "multiply";
		entry2.arg_nums = [2];
		
		auto entry3 = Entry();
		entry3.method = "divide";
		entry3.arg_nums = [2];
		entry3.need_cache = true;
		entry3.reset_caches = ["trusted", "infinity"];
		entry3.reset_by = ["drop", "unsafe"];
		entry3.set_username = true;
		
		table.add(entry1);
		table.add(entry2);
		table.add(entry3);
	}
}

unittest
{
	scope(failure)
	{
		assert(false, "sql_json unittest failed");
	}
	
	initTable();
}

