{# Use the custom schema as the dataset name as-is (default dbt would prefix it: staging_staging). #}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {{ custom_schema_name | trim if custom_schema_name is not none else target.schema }}
{%- endmacro %}
