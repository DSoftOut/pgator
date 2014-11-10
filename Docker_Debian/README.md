##Debian-based docker image

First, build pgator as usual in its directory.

Then:
```bash
$ cp bin/pgator Docker_Debian/
$ sudo docker build -t debian/pgator Docker_Debian/ # builds pgator image
$ sudo docker images | grep pgator
debian/pgator       latest              a7f3cab35061        47 minutes ago      211.9 MB
```

Starting the postgres. Opened port 5432 is need for adding methods table into the clean DB container.
```bash
$ sudo docker run --name some-postgres-container -p 5432:5432 -d postgres:9.4
```

Adding methods table using your favorite postgres client. For example:
```bash
$ psql -h localhost postgres postgres
psql (9.4beta2)
Type "help" for help.

postgres=#
```

```sql
CREATE TABLE pgator_rpc
(
  method text NOT NULL,
  sql_queries text[] NOT NULL,
  arg_nums integer[] NOT NULL,
  set_username boolean NOT NULL DEFAULT false,
  need_cache boolean NOT NULL DEFAULT false,
  read_only boolean NOT NULL DEFAULT false,
  reset_caches text[] NOT NULL DEFAULT '{}'::text[],
  reset_by text[] NOT NULL DEFAULT '{}'::text[],
  commentary text,
  CONSTRAINT json_rpc_pkey PRIMARY KEY (method)
);

INSERT INTO pgator_rpc VALUES (
'test.echo',
'{"select $1::text as passed_value"}',
'{1}',
false,
false,
false,
'{}',
'{}',
''
);
```

Starting the pgator image with linking to the postgresql container:
```bash
$ sudo docker run -d --name some-pgator-container --link some-postgres-container:db --publish=8080:8080 debian/pgator
bcb15a1e149e85cc9ae2e00af4f8f377a62f30c84e0b88d56115f5557b19385d
$ sudo docker ps
CONTAINER ID        IMAGE                  COMMAND                CREATED             STATUS              PORTS                    NAMES
bcb15a1e149e        debian/pgator:latest   "/docker-entrypoint.   2 minutes ago       Up 2 minutes        0.0.0.0:8080->8080/tcp   some-pgator-container     
32eef82435a3        postgres:9.4           "/docker-entrypoint.   49 minutes ago      Up 49 minutes       0.0.0.0:5432->5432/tcp   some-postgres-container
```

Checking pgator replies:
```bash
$ curl -X POST -H 'Content-Type: application/json' -H 'Accept: application/json' --data '
{
    "jsonrpc": "2.0",
    "method": "test.echo",
    "params": [ "Hello, world!" ],
    "id": 1
}' http://localhost:8080/
{
	"id": 1,
	"result": {
		"passed_value": [
			"Hello, world!"
		]
	},
	"jsonrpc": "2.0"
}
```
