-- =============================================================================
-- Dimensión: dim_pais
-- =============================================================================

{{ config(materialized='table', schema='marts') }}

SELECT
    MD5(country)        AS pais_key,
    country             AS nombre_pais
FROM (
    SELECT DISTINCT country
    FROM {{ ref('stg_transactions_unified') }}
    WHERE country IS NOT NULL AND TRIM(country) != ''
) paises
