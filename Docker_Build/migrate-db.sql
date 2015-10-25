DROP TABLE IF EXISTS json_rpc CASCADE;

CREATE TABLE json_rpc
(
  method text NOT NULL, -- API method name (or function name)
  sql_queries text[] NOT NULL, -- a set of SQL queries
  arg_nums integer[] NOT NULL, -- corresponds to number of arguments in each SQL query in sql_queries
  set_username boolean NOT NULL, -- should pgator setup environment variables (they are defined in config file) with data from BasicAuth fields in HTTP request?
  need_cache boolean NOT NULL, -- should pgator cache respond (including errors)?
  read_only boolean NOT NULL, -- does method change data in data base?
  reset_caches text[], -- a list of signals for cache resetting that are generated when method is called
  reset_by text[], -- a list of signals that reset cached of the method
  commentary text,
  result_filter boolean[], -- if set marks which query result should be included in json respond
  one_row_flags boolean[], -- if set marks which query should return only one row (0 or more than 1 will be rollbacked)
  CONSTRAINT json_rpc_pkey2 PRIMARY KEY (method)
);