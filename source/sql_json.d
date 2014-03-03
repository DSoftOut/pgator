// Written in D programming language
/**
* This module contain json<->sql table from db.<br>
*
* Loads on SIGHUP or on startup
*
* Authors: Zaramzan <shamyan.roman@gmail.com>
*
*/
module sql_json;

import std.traits;

import util;

struct Entry
{
	@required
	string method;
	
	@required
	string[] sql_queries;
	
	@required
	uint arg_num;
	
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
	
	const bool isValidParams(in string[] params)
	{
		return params.length == arg_num;
	}
}

//Will expand
shared class SqlJsonTable
{
	private Entry[string] map;
	
	void add(in Entry entry)
	{
		shared Entry ent = toShared(entry);
		map[entry.method] = ent;
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
	
	bool need_cache(string method)
	{
		auto p = method in map;
		
		if (p is null) return false;
		
		auto val = *p;
		
		return val.need_cache && val.read_only;
	}
	
	bool read_only(string method)
	{
		auto p = method in map;
		
		if (p is null) return false;
		
		auto val = *p;
		
		return val.read_only;
	}
	
	string[] reset_caches(string method)
	{
		auto p = method in map;
		
		if (p is null) return null;
		
		auto val = *p;
		
		return cast(string[])(val.reset_caches);
	}
	
	string[] reset_by(string method)
	{
		auto p = method in map;
		
		if (p is null) return null;
		
		auto val = *p;
		
		return cast(string[])(val.reset_by);
	}
	
	string[] needDrop(string method)
	{
		string[] arr = new string[0];
		
		auto p = method in map;
		
		if (p is null) return arr;
		
		auto val = *p;
		
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
		
		return arr;
	}
	
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
	
	Entry getEntry(string method)
	{
		auto p = method in map;
		
		if (p is null) return Entry();
		
		return cast(Entry) *p;
	}
	
	bool methodFound(string method)
	{	
		return (method in map) !is null;
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
		entry1.arg_num = 2;
		entry1.need_cache = true;
		entry1.reset_caches = ["drop", "safe", "pure"];
		entry1.reset_by = ["drop", "unsafe"];
		
		auto entry2 = Entry();
		entry2.method = "multiply";
		entry2.arg_num = 2;
		
		auto entry3 = Entry();
		entry3.method = "divide";
		entry3.arg_num = 2;
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

