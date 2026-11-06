{#
  By default dbt builds a model with a custom schema into "<target schema>_<custom schema>", for example
  default_staging. This project uses fixed schema names that match the layer folders (staging, intermediate,
  marts), so a custom schema is used exactly as written. A model without a custom schema goes to the target schema.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
