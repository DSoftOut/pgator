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
	string method;
	
	string sql_query;
	
	uint arg_num;
	
	bool set_username;
	
	bool need_cache;
	
	bool read_only;
	
	string[] reset_caches;
	
	string[] reset_by;
	
	string commentary;
}

//Will expand
class SqlJsonTable
{
	private Entry[string] map;
	
	void add(Entry entry)
	{
		map[entry.method] = entry;
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
		scope(failure)
		{
			return false;
		}
		
		return map[method].need_cache;
	}
	
	string[] reset_caches(string method)
	{
		scope(failure)
		{
			return new string[0];
		}
		
		return map[method].reset_caches;
	}
	
	string[] reset_by(string method)
	{
		scope(failure)
		{
			return new string[0];
		}
		
		return map[method].reset_by;
	}
	
	bool needDrop(string method)
	{
		if (need_cache(method))
		{
			string[] reset_by = reset_by(method);
			foreach(str1; reset_caches(method))
			{
				foreach(str2; reset_by)
				{
					if (str1 == str2) return true;
				}
			}
		}
		
		return false;
	}
}

private __gshared SqlJsonTable p_table;

SqlJsonTable table() @property
{
	return p_table;
}

version(unittest)
{
	void initTable()
	{
		p_table = new SqlJsonTable();
		
		auto entry1 = Entry();
		entry1.method = "substract";
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
		
		
		p_table.add(entry1);
		p_table.add(entry2);
		p_table.add(entry3);
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

