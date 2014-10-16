pgator
=============
[![Build Status](https://travis-ci.org/DSoftOut/pgator.png?branch=master)](https://travis-ci.org/DSoftOut/pgator)
<img align="right" src="pgator.png" />
[![Stories in Ready](https://badge.waffle.io/dsoftout/pgator.png?label=ready&title=Ready)](https://waffle.io/dsoftout/pgator)
[![Gitter Chat](https://badges.gitter.im/DSoftOut/pgator.png)](https://gitter.im/DSoftOut/pgator)

Server that transforms JSON-RPC calls into SQL queries for PostgreSQL.

[Technical documentation (ongoing)](http://dsoftout.github.io/pgator/app.html)

[Overview-(ru)](https://github.com/DSoftOut/pgator/wiki/Overview-(ru))

###Quick start guide

####Dlang stuff installation (Debian example)

Since pgator written in the Dlang you will need to install the DMD compiler and the DUB builder packages:

```bash
$ cat /etc/apt/sources.list.d/d-apt.list 
deb http://netcologne.dl.sourceforge.net/project/d-apt dmd main #APT repository for D
$ sudo aptitude update
$ sudo aptitude install -t unstable dub dmd
```

####pgator downloading and building

```bash
$ git clone https://github.com/DSoftOut/pgator.git
Cloning into 'pgator'...
remote: Counting objects: 2946, done.
remote: Total 2946 (delta 0), reused 0 (delta 0)
Receiving objects: 100% (2946/2946), 1.53 MiB | 271.00 KiB/s, done.
Resolving deltas: 100% (2087/2087), done.
Checking connectivity... done.
$ cd pgator
$ dub build
```

####Example config

```json
# cat /opt/pgator/etc/pgator.conf 
{
	"sqlServers": [
		{
			"maxConn": 5,
			"connString": "dbname=exampledb user=worker"
		}
	],
	"sqlAuth": [
		"pgator.username",
		"pgator.password"
	],
	"maxConn": 10,
	"port": 8080,
	"sqlTimeout": 1000,
	"logname": "/var/log/pgator/pgator.txt",
	"vibelog": "/var/log/pgator/http.log",
	"logSqlTransactions": true,
	"logJsonQueries": true,
	"sqlJsonTable": "public.json_rpc",

	"userid_disabled": 105,
	"groupid_disabled": 108
}

```

####How to run pgator as daemon

supervisor script example:

```ini
$ cat /etc/supervisor.d/pgator.ini
[program:pgator]
command=/opt/pgator/bin/pgator
directory=/opt/pgator
user=pgator
redirect_stderr=true
stdout_logfile=/var/log/supervisor/pgator.log
stdout_logfile_maxbytes=1MB
stdout_logfile_backups=3
autorestart=true
exitcodes=2
stopasgroup=true

```

####RPC calls table example

Simple method code that just returns one passed argument:

```sql
=> SELECT * FROM json_rpc WHERE method = 'test.echo';
  method   |             sql_queries             | arg_nums | set_username | need_cache | read_only | reset_caches | reset_by |  commentary   
-----------+-------------------------------------+----------+--------------+------------+-----------+--------------+----------+---------------
 test.echo | {"select $1::text as passed_value"} | {1}      | f            | f          | f         | {}           | {}       | Тест возврата+
           |                                     |          |              |            |           |              |          |              +
           |                                     |          |              |            |           |              |          | @Params:     +
           |                                     |          |              |            |           |              |          | $1 - значение+
           |                                     |          |              |            |           |              |          |              +
           |                                     |          |              |            |           |              |          | @Returns:    +
           |                                     |          |              |            |           |              |          | значение
(1 строка)
```

#### JSON-RPC 2.0 methods calling:

Calling a test method described in the previous table:
```json
$ curl -X POST -H 'Content-Type: application/json' -H 'Accept: application/json' --data '
{
    "jsonrpc": "2.0",
    "method": "test.echo",
    "params": [ "Hello, world!" ],
    "id": 1
}' http://pgator-test-server.com:8080/
```

Response:
```json
{
	"id": 1,
	"result": [
		{
			"passed_value": [
				"Hello, world!"
			]
		}
	],
	"jsonrpc": "2.0"
}
```
