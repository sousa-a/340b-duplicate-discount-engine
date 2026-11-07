{#
  Appends one row per test of the current dbt invocation to data_quality.test_results, so every test result is
  kept across runs in a single table (failing rows of individual tests are kept only for singular tests, see
  dbt_project.yml). Called from on-run-end with dbt's `results` object, which holds the outcome of every node run.

  Columns: when the run started, dbt's invocation id, test name and unique id, status (pass, warn, fail, error,
  skipped), number of failing rows, configured severity, seconds taken, and whether failing rows were stored.
  The table is created on first use. Nothing is written when the invocation ran no tests (dbt compile, dbt run).
#}
{% macro log_test_results(results) %}
    {%- if execute -%}
        {%- set tests = results | selectattr('node.resource_type', 'equalto', 'test') | list -%}
        {%- if tests | length > 0 -%}
            {%- set table = target.catalog ~ '.data_quality.test_results' if target.catalog is defined and target.catalog else 'data_quality.test_results' -%}
            {%- do run_query('create schema if not exists ' ~ table.rsplit('.', 1)[0]) -%}
            {%- do run_query(
                'create table if not exists ' ~ table ~ ' ('
                ~ 'run_started_at timestamp, invocation_id string, test_name string, unique_id string, '
                ~ 'status string, failures bigint, severity string, execution_seconds double, '
                ~ 'stored_failures boolean)'
            ) -%}
            insert into {{ table }} values
            {%- for r in tests %}
                (
                    timestamp '{{ run_started_at.strftime("%Y-%m-%d %H:%M:%S") }}',
                    '{{ invocation_id }}',
                    '{{ r.node.name }}',
                    '{{ r.node.unique_id }}',
                    '{{ r.status }}',
                    {{ r.failures if r.failures is not none else 'null' }},
                    '{{ r.node.config.severity }}',
                    {{ r.execution_time | round(3) }},
                    {{ 'true' if r.node.config.store_failures else 'false' }}
                ){{ "," if not loop.last }}
            {%- endfor %}
        {%- else -%}
            select 1
        {%- endif -%}
    {%- else -%}
        select 1
    {%- endif -%}
{% endmacro %}
