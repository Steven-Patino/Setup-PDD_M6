-- =============================================================================
-- Fact Table: fact_ventas
-- =============================================================================
-- Contiene solo registros de VENTAS (quantity > 0, unit_price > 0).
-- Las devoluciones están en fact_devoluciones (separadas por regla de negocio).
-- =============================================================================

{{ config(materialized='table', schema='marts') }}

WITH ventas AS (
    SELECT *
    FROM {{ ref('stg_transactions_unified') }}
    WHERE transaction_type = 'VENTA'
      AND quantity > 0
      AND unit_price > 0
)

SELECT
    transaction_key,
    invoice_no,

    -- Claves foráneas a dimensiones
    MD5(v.stock_code)               AS producto_key,
    MD5(v.customer_id)              AS cliente_key,
    v.invoice_date_utc::DATE::TEXT  AS tiempo_key,
    MD5(v.country)                  AS pais_key,

    -- Métricas
    v.quantity                      AS cantidad,
    v.unit_price,
    v.quantity * v.unit_price       AS revenue_bruto,

    v.invoice_date_utc,
    v.source_file

FROM ventas v
