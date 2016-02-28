DROP TABLE IF EXISTS pgator_calls;

CREATE TABLE pgator_calls
(
  method text NOT NULL,
  sql_query text NOT NULL,
  args text[] NOT NULL,
  one_row_flag boolean,
  --set_username boolean NOT NULL,
  --read_only boolean NOT NULL,
  --commentary text,

  CONSTRAINT pgator_calls_pkey PRIMARY KEY (method)
);

CREATE OR REPLACE FUNCTION show_error(message text, internal boolean default false, error_code text default 'P0001'::text)
RETURNS void LANGUAGE plpgsql AS $_$
begin
        if internal then
                raise '%', message using errcode = error_code;
        else
                raise 'CAUGHT_ERROR: %', message using errcode = error_code;
        end if;
end;
$_$;

INSERT INTO pgator_calls VALUES
('echo', 'SELECT $1::text as echoed', '{"value_for_echo"}', false),
('echo2', 'SELECT $1::text', '{"value_for_echo"}', NULL),
('wrong_sql_statement', 'wrong SQL statement', '{}', false);

INSERT INTO pgator_calls VALUES
('show_error', 'SELECT show_error($1, $2, $3)', '{"msg", "internalFlag", "errorCode"}');
