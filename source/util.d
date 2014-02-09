// Written in D programming language
/**
* Util module
*
* Authors: Zaramzan <shamyan.roman@gmail.com>
*
*/

module util;

mixin template t_field(T, alias fieldName)
{
	mixin("private "~T.stringof~" m_"~fieldName~";");
	
	mixin("private bool f_"~fieldName~";");
	
	mixin(T.stringof~" "~fieldName~"() @property { return m_"~fieldName~";}");
	
	mixin("private void "~fieldName~"("~T.stringof~" f) @property { m_"~fieldName~"= f; f_"~fieldName~"=true;}");
}