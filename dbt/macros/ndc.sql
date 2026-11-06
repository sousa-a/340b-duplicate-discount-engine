{#
  National Drug Code (NDC) helpers.

  An NDC has three segments: labeler, product and package. On labels and in many files it appears as 10 digits with
  hyphens, in one of three configurations: 4-4-2, 5-3-2 or 5-4-1. Billing and pricing files use the 11-digit form
  5-4-2 without hyphens, made by adding a leading zero to the short segment (the standard HIPAA conversion):
    4-4-2  1234-5678-90   ->  0 + 1234 5678 90     01234567890
    5-3-2  12345-678-90   ->  12345 0 + 678 90     12345067890
    5-4-1  12345-6789-0   ->  12345 6789 0 + 0     12345678900
  An 11-digit code written with hyphens (5-4-2) only loses its hyphens.
  A value in none of these forms returns NULL, so it shows up in tests instead of matching the wrong drug.
#}

{% macro normalize_ndc11(column) -%}
    case
        when {{ column }} rlike '^[0-9]{11}$' then {{ column }}
        when {{ column }} rlike '^[0-9]{5}-[0-9]{4}-[0-9]{2}$' then replace({{ column }}, '-', '')
        when {{ column }} rlike '^[0-9]{4}-[0-9]{4}-[0-9]{2}$' then concat('0', replace({{ column }}, '-', ''))
        when {{ column }} rlike '^[0-9]{5}-[0-9]{3}-[0-9]{2}$'
            then concat(substr({{ column }}, 1, 5), '0', substr({{ column }}, 7, 3), substr({{ column }}, 11, 2))
        when {{ column }} rlike '^[0-9]{5}-[0-9]{4}-[0-9]{1}$'
            then concat(substr({{ column }}, 1, 5), substr({{ column }}, 7, 4), '0', substr({{ column }}, 12, 1))
    end
{%- endmacro %}

{# Which of the forms above a value was received in. Kept as a column so data quality can count each form. #}
{% macro ndc_format(column) -%}
    case
        when {{ column }} is null then null
        when {{ column }} rlike '^[0-9]{11}$' then '11-digit'
        when {{ column }} rlike '^[0-9]{5}-[0-9]{4}-[0-9]{2}$' then '5-4-2 hyphenated'
        when {{ column }} rlike '^[0-9]{4}-[0-9]{4}-[0-9]{2}$' then '4-4-2'
        when {{ column }} rlike '^[0-9]{5}-[0-9]{3}-[0-9]{2}$' then '5-3-2'
        when {{ column }} rlike '^[0-9]{5}-[0-9]{4}-[0-9]{1}$' then '5-4-1'
        else 'unrecognized'
    end
{%- endmacro %}
