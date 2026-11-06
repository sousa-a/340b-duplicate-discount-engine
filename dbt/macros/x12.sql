{#
  Helpers for reading X12 segments from the raw edi_*_segments tables.

  The raw column elements is an array whose position 0 is the segment ID, so X12 element 01 is array position 1.
  x12_el(n) returns element n (as numbered in the X12 guides) as text, trimmed, with an empty element as NULL.
  try_element_at is used because with ANSI SQL on, elements[n] fails the whole query when a segment is shorter
  than expected; try_element_at returns NULL instead, and the tests then report the missing value.
  try_element_at counts from 1, hence n + 1.
#}
{% macro x12_el(n, column='elements') -%}
    nullif(trim(try_element_at({{ column }}, {{ n }} + 1)), '')
{%- endmacro %}

{# X12 dates are CCYYMMDD. Returns a date, or NULL when the text is not a valid date. #}
{% macro x12_date(n, column='elements') -%}
    to_date(try_to_timestamp({{ x12_el(n, column) }}, 'yyyyMMdd'))
{%- endmacro %}

{#
  Running count of a segment within its transaction set, in file order. Used to rebuild X12 loops: in the 844 every
  chargeback line starts with CON, so the running count of CON segments is the line number of every segment that
  belongs to that line (0 for the header segments before the first line).
#}
{% macro x12_loop_number(loop_start_segment) -%}
    sum(case when segment_id = '{{ loop_start_segment }}' then 1 else 0 end) over (
        partition by _source_file, st_control_number
        order by segment_position
        rows between unbounded preceding and current row
    )
{%- endmacro %}
