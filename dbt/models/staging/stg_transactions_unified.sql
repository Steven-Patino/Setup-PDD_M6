-- =============================================================================
-- Modelo: stg_transactions_unified
-- Capa:   Staging -> VIEW
-- =============================================================================
-- Unifica ambas fuentes despues de limpiarlas.
--
-- Decisiones documentadas:
--   - Duplicados entre fuentes: se deduplican por
--     (invoice_no, stock_code, fecha truncada al minuto).
--   - Prioridad de fuente: ecommerce_data gana si ambas describen la misma
--     transaccion porque es el volcado diario mas cercano al sistema fuente.
--   - Clientes sin identificador: se conservan como GUEST desde staging.
--   - Cantidad <= 0: se clasifica como DEVOLUCION/ajuste.
-- =============================================================================

{{ config(materialized='view') }}

WITH fuente1 AS (
    SELECT
        *,
        1 AS source_priority
    FROM {{ ref('stg_ecommerce') }}
    WHERE invoice_no IS NOT NULL
      AND stock_code IS NOT NULL
      AND quantity IS NOT NULL
      AND invoice_date_utc IS NOT NULL
      AND unit_price IS NOT NULL
),

fuente2 AS (
    SELECT
        *,
        2 AS source_priority
    FROM {{ ref('stg_online_retail') }}
    WHERE invoice_no IS NOT NULL
      AND stock_code IS NOT NULL
      AND quantity IS NOT NULL
      AND invoice_date_utc IS NOT NULL
      AND unit_price IS NOT NULL
),

unificado AS (
    SELECT * FROM fuente1
    UNION ALL
    SELECT * FROM fuente2
),

deduplicado AS (
    SELECT
        *,
        DATE_TRUNC('minute', invoice_date_utc) AS dedupe_minute,
        ROW_NUMBER() OVER (
            PARTITION BY
                invoice_no,
                stock_code,
                DATE_TRUNC('minute', invoice_date_utc)
            ORDER BY source_priority ASC, invoice_date_utc ASC
        ) AS rn
    FROM unificado
)

SELECT
    MD5(
        invoice_no || '|' ||
        stock_code || '|' ||
        dedupe_minute::TEXT || '|' ||
        COALESCE(customer_id, 'GUEST') || '|' ||
        COALESCE(country, '')
    ) AS transaction_key,
    invoice_no,
    stock_code,
    description,
    quantity,
    invoice_date_utc,
    unit_price,
    quantity * unit_price AS revenue_bruto,
    customer_id,
    country,
    transaction_type,
    source_file
FROM deduplicado
WHERE rn = 1
