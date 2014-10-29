##Debian-based docker image

First, build pgator as usual in its directory.

Then:
```bash
$ cp bin/pgator Docker_Debian/
$ sudo docker build -t pgator Docker_Debian/
```
This builds a pgator docker image.

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
