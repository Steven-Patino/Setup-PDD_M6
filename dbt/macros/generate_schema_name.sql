-- =============================================================================
-- Macro: generate_schema_name
-- =============================================================================
-- Por defecto, dbt prefija el schema del target al nombre del schema custom.
-- Ejemplo: si target.schema = 'public' y +schema: 'staging', dbt crea 'public_staging'.
-- Con esta macro, si defines +schema: 'staging', dbt crea exactamente 'staging'.
-- Esto garantiza que los schemas se llamen raw, staging y marts exactamente.
-- =============================================================================

{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
