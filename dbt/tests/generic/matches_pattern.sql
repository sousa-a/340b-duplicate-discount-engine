{#
  Format test: every non-empty value must match a regular expression (Spark SQL rlike, Java regex syntax).
  Returns the rows that do not match. Empty values are left to not_null.
  Example in a .yml:  - matches_pattern: {arguments: {pattern: "^[0-9]{11}$"}}
#}
{% test matches_pattern(model, column_name, pattern) %}
{#
  Severity warn by default: a malformed value is a data quality finding, kept in the data_quality schema, but it
  must not stop the build. dbt build skips every model downstream of a failing (error) test, so one bad value in
  one file would otherwise hold back the whole engine. Keys stay strict: unique and not_null on identifiers are errors.
#}
{{ config(severity = 'warn') }}
select {{ column_name }} as failing_value, *
from {{ model }}
where {{ column_name }} is not null
  and not ({{ column_name }} rlike '{{ pattern }}')
{% endtest %}
