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
import std.conv;

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
	
	@possible
	bool[] result_filter;
	
	@possible
	bool[] one_row_flags;
	
	const bool isValidParams(in string[] params, out size_t expected)
	{
	    expected = reduce!"a+b"(0, arg_nums);
		return params.length == expected;
	}
	
	const bool isValidFilter(out size_t expected)
	{
	    expected = sql_queries.length;
	    if(!needResultFiltering) return true;
	    else return result_filter.length == sql_queries.length;
	}
	
	const bool isValidOneRowConstraint(out size_t expected)
	{
	    expected = sql_queries.length;
	    if(!needOneRowCheck) return true;
	    else return one_row_flags.length == sql_queries.length;
	}
	
	const bool needResultFiltering()
	{
	    return result_filter && result_filter != [];
	}
	
	const bool needOneRowCheck()
	{
	    return one_row_flags && one_row_flags != [];
	}
	
	const shared(Entry) toShared() @property
	{
		auto res = this;
		
		return cast(shared Entry) res;
	}
	
	void toString(scope void delegate(const(char)[]) sink) const
	{
	    sink("method: "); sink(method); sink("\n");
	    sink("set_username: "); sink(set_username.to!string); sink("\n");
	    sink("need_cache: "); sink(need_cache.to!string); sink("\n");
	    sink("read_only: "); sink(read_only.to!string); sink("\n");
	    sink("reset_caches: "); sink(reset_caches.to!string); sink("\n");
	    sink("reset_by: "); sink(reset_by.to!string); sink("\n");
	    sink("commentary: "); sink(commentary); sink("\n");
	    foreach(immutable i, query; sql_queries)
	    {
	        sink("\t"); sink("query: "); sink(query); sink("\n");
	        if(arg_nums && arg_nums != [])
	        {
	            sink("\t\t"); sink("argnums: "); sink(arg_nums[i].to!string); sink("\n");
            } else
            {
                sink("\t\targnums: 0\n");
            }
            if(result_filter && result_filter != [])
            {
                sink("\t\t"); sink("filter: "); sink(result_filter[i].to!string); sink("\n");
            } else
            {
                sink("\t\tfilter: true\n");
            }
            if(one_row_flags && one_row_flags != [])
            {
                sink("\t\t"); sink("is_one_row: "); sink(one_row_flags[i].to!string); sink("\n");
            } else
            {
                sink("\t\t"); sink("is_one_row: false \n");
            }
        } 
	}
}

/**
* Contains methods descriptions, cache rules, etc
* 
* Authors: Zaramzan <shamyan.roman@gmail.com>
*/
class SqlJsonTable
{
    shared
    {
	
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
    	* Returns: set_username in json_rpc
    	*/
    	bool needAuth(string method)
    	{
    		shared Entry* p;
    		
    		p = method in map;
    		
    		if (p)
    		{
    			auto entry = cast(Entry) *p;
    			
    			return entry.set_username;
    		}
    		
    		return false;
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
    	
    	/// Makes drop map
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
    		
    		// TODO: Check if it regression in 2.066-b1
    		(cast(shared(string[])[string])dropMap).rehash();
    	}
	}
    
	void toString(scope void delegate(const(char)[]) sink) const
	{
	    sink("SqlJsonTable(\n");
	    foreach(entry; map)
	    {
	        sink(entry.to!string);
	    }
	    sink(")\n");
	}
	
	private
	{	
    	alias string[] dropArr;
    	Entry[string] map;
    	dropArr[string] dropMap;
	}
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

