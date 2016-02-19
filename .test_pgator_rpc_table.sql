DROP TABLE IF EXISTS pgator_rpc;

CREATE TABLE pgator_rpc
(
  method text NOT NULL,
  sql_query text NOT NULL,
  args text[] NOT NULL,
  --set_username boolean NOT NULL,
  --read_only boolean NOT NULL,
  --commentary text,
  one_row_flag boolean,

  CONSTRAINT pgator_rpc_pkey PRIMARY KEY (method)
);

INSERT INTO pgator_rpc VALUES
('echo', 'SELECT $1::text as echoed', '{"value_for_echo"}', false),
('echo2', 'SELECT $1::text', '{"value_for_echo"}', NULL),
('wrong_sql_statement', 'wrong SQL statement', '{}', false);
