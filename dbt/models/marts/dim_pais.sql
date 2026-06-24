-- =============================================================================
-- Dimensión: dim_pais
-- =============================================================================
-- Se normaliza a mayusculas y se conservan solo paises realmente presentes en
-- las transacciones limpias.
-- =============================================================================

{{ config(
    materialized='table',
    schema='marts',
    post_hook=["ALTER TABLE \"{{ target.database }}\".\"marts\".\"dim_pais\" ADD CONSTRAINT pk_dim_pais PRIMARY KEY (pais_key)"]
) }}

WITH paises AS (
    SELECT DISTINCT
        country
    FROM {{ ref('stg_transactions_unified') }}
    WHERE country IS NOT NULL
      AND BTRIM(country) <> ''
)

SELECT
    MD5(country) AS pais_key,
    country      AS nombre_pais
FROM paises
