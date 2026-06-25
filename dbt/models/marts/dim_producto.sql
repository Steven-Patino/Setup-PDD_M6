-- =============================================================================
-- Dimensión: dim_producto
-- =============================================================================
-- Canonico por codigo de producto:
--   - Se usa la descripcion normalizada mas frecuente.
--   - Si hay empate, se prefiere la descripcion mas larga y luego la alfabética.
-- Categoría:
--   - Estrategia sin API: clasificacion por palabras clave en la descripcion.
-- =============================================================================

{{ config(
    materialized='table',
    schema='marts',
    pre_hook=["ALTER TABLE IF EXISTS \"{{ target.database }}\".\"marts\".\"dim_producto\" DROP CONSTRAINT IF EXISTS pk_dim_producto"],
    post_hook=["ALTER TABLE \"{{ target.database }}\".\"marts\".\"dim_producto\" ADD CONSTRAINT pk_dim_producto PRIMARY KEY (producto_key)"]
) }}

WITH descripciones AS (
    SELECT
        stock_code,
        description,
        COUNT(*) AS frecuencia
    FROM {{ ref('stg_transactions_unified') }}
    WHERE stock_code IS NOT NULL
      AND description IS NOT NULL
    GROUP BY 1, 2
),

descripcion_canonica AS (
    SELECT DISTINCT ON (stock_code)
        stock_code,
        description AS nombre_canonico
    FROM descripciones
    ORDER BY
        stock_code,
        frecuencia DESC,
        LENGTH(description) DESC,
        description ASC
),

con_categoria AS (
    SELECT
        stock_code,
        nombre_canonico,
        CASE
            WHEN nombre_canonico LIKE '%LIGHT%'
              OR nombre_canonico LIKE '%LAMP%'
              OR nombre_canonico LIKE '%CANDLE%'
              OR nombre_canonico LIKE '%LANTERN%'
              OR nombre_canonico LIKE '%GLASS BALL%'
                THEN 'Iluminacion'
            WHEN nombre_canonico LIKE '%BAG%'
              OR nombre_canonico LIKE '%BASKET%'
              OR nombre_canonico LIKE '%LUNCH%'
                THEN 'Accesorios'
            WHEN nombre_canonico LIKE '%CLOCK%'
              OR nombre_canonico LIKE '%FRAME%'
              OR nombre_canonico LIKE '%BOX%'
              OR nombre_canonico LIKE '%SEWING%'
              OR nombre_canonico LIKE '%BUILDING BLOCK%'
                THEN 'Hogar'
            WHEN nombre_canonico LIKE '%HEART%'
              OR nombre_canonico LIKE '%ORNAMENT%'
              OR nombre_canonico LIKE '%BIRD%'
              OR nombre_canonico LIKE '%TREE%'
                THEN 'Decoracion'
            WHEN nombre_canonico LIKE '%POSTAGE%'
              OR nombre_canonico LIKE '%DOTCOM%'
              OR nombre_canonico LIKE '%MANUAL%'
                THEN 'Logistica'
            ELSE 'General'
        END AS categoria
    FROM descripcion_canonica
)

SELECT
    MD5(stock_code) AS producto_key,
    stock_code      AS codigo_producto,
    nombre_canonico,
    categoria
FROM con_categoria
