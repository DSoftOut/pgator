DROP TABLE IF EXISTS pgator_tests;

CREATE TABLE pgator_tests
(
  -- Required parameters
  method text NOT NULL,
  sql_query text NOT NULL,
  args text[] NOT NULL,

  -- Optional parameters
  result_format text DEFAULT 'TABLE', -- NOT NULL skipped for testing purposes
  read_only boolean NOT NULL DEFAULT FALSE,
  set_auth_variables boolean NOT NULL DEFAULT FALSE,
  statement_num smallint,
  result_name text
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

-- Multi-statement transactions test
INSERT INTO pgator_tests (method, result_name, statement_num, sql_query, args, result_format) VALUES
('multi_tran', 'first_result',  0, 'VALUES (1,3,5), (2,4,6)', '{}', 'TABLE'),
('multi_tran', 'second_result', 1, 'SELECT $1::text', '{"value_1"}', 'CELL'),
('multi_tran', 'third_result',  2, 'SELECT $1::int8', '{"value_2"}', 'CELL'),
('multi_tran', 'void_result',   3, 'VALUES (9,9,9), (9,9,9)', '{}', 'VOID');
