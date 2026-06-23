-- =============================================================================
-- Fact Table: fact_devoluciones
-- =============================================================================
-- Contiene todos los registros de DEVOLUCIONES (quantity <= 0).
-- El revenue_devolucion se almacena como valor POSITIVO para facilitar los
-- cálculos de revenue_neto = revenue_ventas - revenue_devoluciones.
-- =============================================================================

{{ config(materialized='table', schema='marts') }}

WITH devoluciones AS (
    SELECT *
    FROM {{ ref('stg_transactions_unified') }}
    WHERE transaction_type = 'DEVOLUCION'
)

SELECT
    transaction_key,
    invoice_no,

    MD5(d.stock_code)               AS producto_key,
    MD5(d.customer_id)              AS cliente_key,
    d.invoice_date_utc::DATE::TEXT  AS tiempo_key,
    MD5(d.country)                  AS pais_key,

    ABS(d.quantity)                 AS cantidad_devuelta,
    d.unit_price,
    -- Valor positivo: facilita la resta en el cálculo de revenue_neto
    ABS(d.quantity * d.unit_price)  AS revenue_devolucion,

    d.invoice_date_utc,
    d.source_file

FROM devoluciones d
