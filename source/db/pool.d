// Written in D programming language
/**
*	Module describes connection pool to data bases. Pool handles
*	several connections to one or more sql servers. If connection
*	is lost, pool tries to reconnect over $(B reconnectTime) duration.
*	
*	Authors: NCrashed <ncrashed@gmail.com>
*/
module db.pool;

import core.time;

/**
*	The exception is thrown when there is no any free connection
*	for $(B freeConnTimeout) duration while trying to lock one.
*/
class ConnTimeoutException : Exception
{
	@safe pure nothrow this(string file = __FILE__, size_t line = __LINE__)
	{
		super("There is no any free connection to SQL servers!", file, line); 
	}
}

/**
*	Pool handles several connections to one or more SQL servers. If 
*	connection is lost, pool tries to reconnect over $(B reconnectTime) 
*	duration.
*
*	
*/
interface IConnectionPool
{
	/**
	*	Adds connection string to a SQL server with
	*	maximum connections count.
	*
	*	The pool will try to reconnect to the sql 
	*	server every $(B reconnectTime) is connection
	*	is dropped (or is down initially).
	*/
	void addServer(string connString, uint connNum);
	
	/**
	*	If connection to a SQL server is down,
	*	the pool tries to reestablish it every
	*	time units returned by the method. 
	*/
	Duration reconnectTime() @property;
	
	/**
	*	If there is no free connection for 
	*	specified duration while trying to
	*	initialize SQL query, then the pool
	*	throws $(B ConnTimeoutException) exception.
	*/
	Duration freeConnTimeout() @property;
	
	/**
	*	Returns current alive connections number.
	*/
	uint aliveConnections() @property;
	
	/**
	*	Awaits all queries to finish and then closes each connection.
	*	Calls $(B callback) when connections are closed.
	*/
	void finalize(void delegate() callback);
}
