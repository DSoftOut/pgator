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

Since pgator written in the Dlang you will need to install the DMD or LDC2 compiler and the DUB package builder:

```bash
$ cat /etc/apt/sources.list.d/d-apt.list 
deb http://netcologne.dl.sourceforge.net/project/d-apt dmd main #APT repository for D
$ sudo aptitude update
$ sudo aptitude install -t unstable ldc dub
```

####pgator downloading and building

```bash
$ git clone --depth=1 https://github.com/DSoftOut/pgator.git
$ cd pgator
$ dub build --build=release --compiler=ldc2
```

####Example config

```json
{
	"sqlServer":
	{
		"maxConn": 3,
		"connString": "host=192.68.0.1 dbname=exampledb user=worker"
	},
	"sqlAuthVariables": {
		"username": "pgator.username",
		"password": "pgator.password"
	},
	"listenAddresses": ["127.0.0.1", "::1"],
	"listenPort": 8080,
	"sqlPgatorTable": "pgator_calls"
}
```

####How to run pgator as daemon

Please use systemd or somethig like that.

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
SELECT method, sql_query, args, result_format FROM pgator_calls WHERE method = 'test.echo';
  method   |            sql_query            |       args       | result_format 
-----------+---------------------------------+------------------+---------------
 test.echo | select $1::text as passed_value | {value_for_echo} | CELL
(1 row)
```

#### JSON-RPC 2.0 methods calling:

At first, it is need to start pgator:
```
$ ./pgator --config=my_pgator.conf 
Number of methods in the table "pgator_calls": 1, failed to prepare: 0
Listening for requests on http://127.0.0.1:8083/
Listening for requests on http://[::1]:8083/

```

Calling a test method described in the previous table:
```json
$ curl -X POST -H 'Content-Type: application/json' -H 'Accept: application/json' --data '
{
    "jsonrpc": "2.0",
    "method": "test.echo",
    "params": { "value_for_echo": "Hello, world!" },
    "id": 1
}' http://pgator-test-server.com:8080/
```

Response:
```json
{"jsonrpc":"2.0","result":"Hello, world!","id":1}
```
