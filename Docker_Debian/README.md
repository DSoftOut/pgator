##Debian-based docker image

First, build pgator as usual in its directory.

Then:
```bash
$ cp bin/pgator Docker_Debian/
$ sudo docker build -t debian/pgator Docker_Debian/ # builds pgator image
$ sudo docker images | grep pgator
debian/pgator       latest              a7f3cab35061        47 minutes ago      211.9 MB
```

Starting the postgres. Opened port 5432 is need for adding methods table into the DB.
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

Starting the pgator image:

```bash
$ sudo docker run -d --restart=always --name some-pgator-container --link some-postgres-container:db --publish=8080:8080 debian/pgator
cbcc900ac2d3219103056b57dc3975b813ae5b0badf1b4f21aab074c992d1d90
```
