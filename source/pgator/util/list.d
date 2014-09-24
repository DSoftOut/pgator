// Written in D programming language
/**
*    Copyright: © 2014 DSoftOut
*    License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*    Authors: NCrashed <ncrashed@gmail.com>
*/
module pgator.util.list;

import std.algorithm;
import std.container.dlist;
import std.range;

/// Removes one element from the list
/**
*   NEVER use while iterating the $(B list).
*/
void removeOne(T)(ref DList!T list, T elem)
{
   auto toRemove = list[].find(elem).take(1);
   list.linearRemove(toRemove);
}