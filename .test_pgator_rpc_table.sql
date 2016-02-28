DROP TABLE IF EXISTS pgator_rpc;

CREATE TABLE pgator_rpc
(
  method text NOT NULL,
  sql_query text NOT NULL,
  args text[] NOT NULL,
  one_row_flag boolean,
  --set_username boolean NOT NULL,
  --read_only boolean NOT NULL,
  --commentary text,

  CONSTRAINT pgator_rpc_pkey PRIMARY KEY (method)
);

CREATE OR REPLACE FUNCTION show_error(message text, internal boolean default false, error_code text default 'P0001'::text)
RTURNS void LANGUAGE plpgsql AS $_$
begin
        if internal then
                raise '%', message using errcode = error_code;
        else
                raise 'CAUGHT_ERROR: %', message using errcode = error_code;
        end if;
end;
$_$;

INSERT INTO pgator_rpc VALUES
('echo', 'SELECT $1::text as echoed', '{"value_for_echo"}', false),
('echo2', 'SELECT $1::text', '{"value_for_echo"}', NULL),
('wrong_sql_statement', 'wrong SQL statement', '{}', false),
('show_error', 'SELECT show_error($1, $2, $3)', '{"msg", "internalFlag", "errorCode"}');
