// Written in D programming language
/**
*    Copyright: © 2014 DSoftOut
*    License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*    Authors: NCrashed <ncrashed@gmail.com>
*/
module pgator.util.string;

static if (__VERSION__ < 2066) { // from phobos 2.066-b1
	import std.c.string;
	
	/++
	    Returns a D-style array of $(D char) given a zero-terminated C-style string.
	    The returned array will retain the same type qualifiers as the input.
	
	    $(RED Important Note:) The returned array is a slice of the original buffer.
	    The original data is not changed and not copied.
	+/
	
	inout(char)[] fromStringz(inout(char)* cString) @system pure {
	    return cString ? cString[0 .. strlen(cString)] : null;
	}
	
	///
	@system pure unittest
	{
	    assert(fromStringz(null) == null);
	    assert(fromStringz("foo") == "foo");
	}
} else {
	public import std.string: fromStringz;
}