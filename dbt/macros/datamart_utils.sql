{% macro normalize_code(column_name) -%}
UPPER(REGEXP_REPLACE(BTRIM(CAST({{ column_name }} AS TEXT)), '\s+', '', 'g'))
{%- endmacro %}


{% macro normalize_description(column_name) -%}
UPPER(REGEXP_REPLACE(BTRIM(CAST({{ column_name }} AS TEXT)), '\s+', ' ', 'g'))
{%- endmacro %}


{% macro safe_integer(column_name) -%}
CASE
    WHEN NULLIF(BTRIM(CAST({{ column_name }} AS TEXT)), '') IS NULL THEN NULL
    WHEN BTRIM(CAST({{ column_name }} AS TEXT)) ~ '^-?\d+$'
        THEN BTRIM(CAST({{ column_name }} AS TEXT))::INTEGER
    WHEN BTRIM(CAST({{ column_name }} AS TEXT)) ~ '^-?\d+\.0+$'
        THEN ROUND(BTRIM(CAST({{ column_name }} AS TEXT))::NUMERIC)::INTEGER
    ELSE NULL
END
{%- endmacro %}


{% macro safe_numeric(column_name) -%}
CASE
    WHEN NULLIF(BTRIM(CAST({{ column_name }} AS TEXT)), '') IS NULL THEN NULL
    WHEN REGEXP_REPLACE(BTRIM(CAST({{ column_name }} AS TEXT)), ',', '', 'g')
        ~ '^-?\d+(\.\d+)?$'
        THEN REGEXP_REPLACE(BTRIM(CAST({{ column_name }} AS TEXT)), ',', '', 'g')::NUMERIC(18, 4)
    ELSE NULL
END
{%- endmacro %}


{% macro add_pk_if_missing(database_name, schema_name, table_name, constraint_name, column_name) -%}
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint c
        JOIN pg_class t ON c.conrelid = t.oid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = '{{ schema_name }}'
          AND t.relname = '{{ table_name }}'
          AND c.conname = '{{ constraint_name }}'
    ) THEN
        EXECUTE format(
            'ALTER TABLE %I.%I.%I ADD CONSTRAINT %I PRIMARY KEY (%I)',
            '{{ database_name }}',
            '{{ schema_name }}',
            '{{ table_name }}',
            '{{ constraint_name }}',
            '{{ column_name }}'
        );
    END IF;
END $$;
{%- endmacro %}


{% macro add_fk_if_missing(database_name, schema_name, table_name, constraint_name, column_name, ref_database_name, ref_schema_name, ref_table_name, ref_column) -%}
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint c
        JOIN pg_class t ON c.conrelid = t.oid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = '{{ schema_name }}'
          AND t.relname = '{{ table_name }}'
          AND c.conname = '{{ constraint_name }}'
    ) THEN
        EXECUTE format(
            'ALTER TABLE %I.%I.%I ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES %I.%I.%I(%I)',
            '{{ database_name }}',
            '{{ schema_name }}',
            '{{ table_name }}',
            '{{ constraint_name }}',
            '{{ column_name }}',
            '{{ ref_database_name }}',
            '{{ ref_schema_name }}',
            '{{ ref_table_name }}',
            '{{ ref_column }}'
        );
    END IF;
END $$;
{%- endmacro %}
