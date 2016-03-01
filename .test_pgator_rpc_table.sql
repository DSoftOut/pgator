DROP TABLE IF EXISTS pgator_tests;

CREATE TABLE pgator_tests
(
  -- Required parameters
  method text NOT NULL,
  sql_query text NOT NULL,
  args text[] NOT NULL,

  -- Optional parameters
  one_row_flag boolean DEFAULT FALSE, -- NOT NULL skipped for testing purposes
  read_only boolean NOT NULL DEFAULT FALSE,
  set_username boolean NOT NULL DEFAULT FALSE,

  CONSTRAINT pgator_tests_pkey PRIMARY KEY (method)
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

INSERT INTO pgator_tests VALUES
('echo', 'SELECT $1::text as echoed', '{"value_for_echo"}', false),
('null_flag_test', 'SELECT $1::text', '{"value_for_echo"}', NULL),
('wrong_sql_statement', 'wrong SQL statement', '{}', false);

INSERT INTO pgator_tests
(method, sql_query, args)
VALUES
('one_line', 'SELECT ''val1''::text as col1, ''val2''::text as col2', '{}'),
('two_lines', 'VALUES (1,3,5), (2,4,6)', '{}'),
('show_error', 'SELECT show_error($1, $2, $3)', '{"msg", "internalFlag", "errorCode"}');

INSERT INTO pgator_tests
(method, sql_query, args, one_row_flag)
VALUES
('one_row_flag', 'SELECT ''val1'' as col1, ''val2'' as col2', '{}', true);
