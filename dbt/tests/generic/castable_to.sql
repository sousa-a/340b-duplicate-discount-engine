{#
  Validity test for raw text columns: every non-empty value must convert to the given type.
  Returns the rows that do not convert (try_cast gives NULL instead of failing), so a failure lists the exact values.
  Empty values are left to not_null, which keeps "missing" and "malformed" as two separate findings.
  Example in a .yml:  - castable_to: {arguments: {data_type: "decimal(18,6)"}}
#}
{% test castable_to(model, column_name, data_type) %}
{#
  Severity warn by default: a malformed value is a data quality finding, kept in the data_quality schema, but it
  must not stop the build. dbt build skips every model downstream of a failing (error) test, so one bad value in
  one file would otherwise hold back the whole engine. Keys stay strict: unique and not_null on identifiers are errors.
#}
{{ config(severity = 'warn') }}
select {{ column_name }} as failing_value, *
from {{ model }}
where {{ column_name }} is not null
  and try_cast({{ column_name }} as {{ data_type }}) is null
{% endtest %}
