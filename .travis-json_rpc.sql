CREATE TABLE json_rpc
(
  method text NOT NULL,
  sql_queries text[] NOT NULL,
  arg_nums integer[] NOT NULL,
  set_username boolean NOT NULL,
  need_cache boolean NOT NULL,
  read_only boolean NOT NULL,
  reset_caches text[],
  reset_by text[],
  commentary text,
  result_filter boolean[],
  one_row_flags boolean[],
  CONSTRAINT json_rpc_pkey PRIMARY KEY (method)
)
WITH (
  OIDS=FALSE
);
ALTER TABLE json_rpc
  OWNER TO postgres;
