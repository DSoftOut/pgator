// Written in D programming language
/**
* This module contain json_rpc table from db.<br>
*
* Loads on SIGHUP or on startup
*
* Authors: Zaramzan <shamyan.roman@gmail.com>
*
*/
module table;

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

class Table
{
	private Entry[string] map;
	
	void add(Entry entry)
	{
		map[entry.method] = entry;
	}
	
	void reset()
	{
		foreach(key; map.byKey())
		{
			map.remove(key);
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
	
	bool mayDrop(string method)
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
