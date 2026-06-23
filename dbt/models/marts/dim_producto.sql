-- =============================================================================
-- Dimensión: dim_producto
-- =============================================================================
-- Genera un registro único por código de producto con:
--   - Nombre canónico: se elige la descripción más frecuente (en mayúsculas).
--     Esto resuelve el caso "ALARM CLOCK BAKELIKE PINK" vs "alarm clock bakelike pink".
--   - Categoría: asignada por palabras clave en la descripción.
--     (Estrategia sin API: basada en los propios datos de las transacciones)
-- =============================================================================

{{ config(materialized='table', schema='marts') }}

WITH todas_descripciones AS (
    SELECT
        stock_code,
        description,
        COUNT(*) AS frecuencia
    FROM {{ ref('stg_transactions_unified') }}
    WHERE stock_code IS NOT NULL
    GROUP BY stock_code, description
),

-- Para cada producto, quedarse con la descripción más frecuente
descripcion_canonica AS (
    SELECT DISTINCT ON (stock_code)
        stock_code,
        description AS nombre_canonico
    FROM todas_descripciones
    ORDER BY stock_code, frecuencia DESC
),

-- Asignar categoría según palabras clave (reemplaza la API de catálogo)
con_categoria AS (
    SELECT
        stock_code,
        nombre_canonico,
        CASE
            WHEN nombre_canonico LIKE '%LIGHT%'
              OR nombre_canonico LIKE '%LAMP%'
              OR nombre_canonico LIKE '%GLASS BALL%'
              OR nombre_canonico LIKE '%CANDLE%'    THEN 'Iluminacion'
            WHEN nombre_canonico LIKE '%BAG%'
              OR nombre_canonico LIKE '%LUNCH%'     THEN 'Accesorios'
            WHEN nombre_canonico LIKE '%CLOCK%'
              OR nombre_canonico LIKE '%FRAME%'
              OR nombre_canonico LIKE '%SEWING%'
              OR nombre_canonico LIKE '%BUILDING BLOCK%'
              OR nombre_canonico LIKE '%BOX%'       THEN 'Hogar'
            WHEN nombre_canonico LIKE '%WARMER%'
              OR nombre_canonico LIKE '%ORNAMENT%'
              OR nombre_canonico LIKE '%BIRD%'
              OR nombre_canonico LIKE '%HEART%'     THEN 'Decoracion'
            WHEN nombre_canonico LIKE '%POSTAGE%'
              OR nombre_canonico LIKE '%DOTCOM%'
              OR nombre_canonico LIKE '%MANUAL%'    THEN 'Logistica'
            ELSE 'General'
        END AS categoria
    FROM descripcion_canonica
)

SELECT
    -- Clave surrogada: MD5 del stock_code (estable entre ejecuciones)
    MD5(stock_code)             AS producto_key,
    stock_code                  AS codigo_producto,
    nombre_canonico,
    categoria
FROM con_categoria
