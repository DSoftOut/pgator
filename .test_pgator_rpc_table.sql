DROP TABLE IF EXISTS pgator_tests;

CREATE TABLE pgator_tests
(
  -- Required parameters
  method text NOT NULL, -- Method name
  sql_query text NOT NULL, -- SQL code snippet for this method
  args text[] NOT NULL, -- Array of arguments names

  -- Optional parameters
  --
  -- Call result format can be one of theese types:
  -- 'TABLE' (default) - just SQL table returned by SQL query specified in sql_query
  -- 'ROTATED' - similar as 'TABLE' but returns field names specified for each value
  -- 'ROW' - specifies that the query returns strictly one row
  -- 'CELL' - specifies that the query returns strictly one row with one field
  -- 'VOID' - specifies that the SQL statement result will be omitted (only for multi-statement methods)
  result_format text DEFAULT 'TABLE', -- (NOT NULL skipped for testing purposes)
  read_only boolean NOT NULL DEFAULT FALSE, -- read-only SQL query constraint
  set_auth_variables boolean NOT NULL DEFAULT FALSE, -- place HTTP basic auth username and password into sqlAuthVariables variables
  statement_num smallint, -- statement number of multi-statement method
  result_name text -- statement result name of multi-statement method
);

CREATE UNIQUE INDEX ON pgator_tests (method, coalesce(statement_num, -1));

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
('echo', 'SELECT $1::bigint as echoed', '{"value_for_echo"}', 'TABLE'),
('null_flag_test', 'SELECT $1::text', '{"value_for_echo"}', NULL),
('record_returning', 'select val from (values (1,2),(3,4)) val', '{}', 'TABLE'),
('wrong_sql_statement', 'wrong SQL statement', '{}', 'TABLE');

INSERT INTO pgator_tests
(method, sql_query, args)
VALUES
('one_line', 'SELECT $1::text as col1, $2::text as col2', '{"arg1", "arg2"}'::text[]),
('two_lines', 'VALUES (1,3,5), (2,4,6)', '{}'),
('show_error', 'SELECT show_error($1, $2, $3)', '{"msg", "internalFlag", "errorCode"}');

INSERT INTO pgator_tests (method, sql_query, args, result_format)
VALUES ('one_row_flag', 'SELECT ''val1''::text as col1, ''val2''::text as col2', '{}', 'ROW');

INSERT INTO pgator_tests (method, sql_query, args, result_format)
VALUES ('one_cell_flag', 'SELECT 123 as col1', '{}', 'CELL');

INSERT INTO pgator_tests (method, sql_query, args, result_format)
VALUES ('rotated', 'VALUES (1,2,3), (4,5,6)', '{}', 'ROTATED');

INSERT INTO pgator_tests (method, sql_query, args, read_only)
VALUES ('read_only', 'INSERT INTO pgator_tests VALUES(''a'', ''b'', ''{}'')', '{}', true);

INSERT INTO pgator_tests (method, sql_query, args, set_auth_variables, result_format)
VALUES ('echo_auth_variables', 'SELECT current_setting(''pgator.username'') as user, current_setting(''pgator.password'') as pass', '{}', true, 'ROW');

INSERT INTO pgator_tests (method, sql_query, args, result_format)
VALUES ('echo_array', 'SELECT $1::bigint[] as echoed', '{"arr_value"}', 'ROW');

INSERT INTO pgator_tests (method, sql_query, args, result_format)
VALUES ('echo_json', 'SELECT $1::json as echoed', '{"json_value"}', 'CELL');

INSERT INTO pgator_tests (method, sql_query, args, result_format) VALUES
('echo_numeric', 'SELECT $1::numeric', '{"value_for_echo"}', 'CELL'),
('echo_numeric_result', 'SELECT $1::text::numeric', '{"value_for_echo"}', 'CELL'),
('echo_fixedstring', 'SELECT $1::text::char(6)', '{"value_for_echo"}', 'CELL'),
('echo_bigint', 'SELECT $1::bigint', '{"value_for_echo"}', 'CELL'),
('echo_float8', 'SELECT $1::float8', '{"value_for_echo"}', 'CELL'),
('echo_text', 'SELECT $1::text', '{"value_for_echo"}', 'CELL');

-- Multi-statement transactions test
INSERT INTO pgator_tests (method, result_name, statement_num, sql_query, args, result_format) VALUES
('multi_tran', 'first_result',  0, 'VALUES (1,3,5), (2,4,6)', '{}', 'TABLE'),
('multi_tran', 'second_result', 1, 'SELECT $1::text', '{"value_1"}', 'CELL'),
('multi_tran', 'third_result',  2, 'SELECT $1::int8', '{"value_2"}', 'CELL'),
('multi_tran', 'void_result',   3, 'VALUES (9,9,9), (9,9,9)', '{}', 'VOID');

-- Vibe.d REST struct test
INSERT INTO pgator_tests (method, sql_query, args, result_format)
VALUES ('rest1', 'SELECT $1::text as v1, $2::bigint as v2', '{"value1", "value2"}', 'ROW');
