-- =============================================================================
-- Modelo: stg_online_retail
-- Fuente: raw.online_retail_ii (online_retail_II.csv — Fuente 2: Kaggle historial)
-- Capa:   Staging → VIEW
-- =============================================================================
-- Diferencias con la Fuente 1 que este modelo normaliza:
--   - Columna 'invoice'   → renombrada a invoice_no  (misma lógica)
--   - Columna 'price'     → renombrada a unit_price
--   - Columna 'customer_id' ya viene con espacio en el CSV ("Customer ID")
--     pero el DAG la carga como customer_id (ver etl_pipeline_dag.py)
--   - Formato de fecha diferente: YYYY-MM-DD HH:MM:SS  en lugar de M/D/YYYY H:MM
-- =============================================================================

{{ config(materialized='view') }}

WITH source AS (
    SELECT * FROM {{ source('raw', 'online_retail_ii') }}
),

cleaned AS (
    SELECT
        UPPER(TRIM(invoice))                            AS invoice_no,
        UPPER(TRIM(stock_code))                         AS stock_code,
        UPPER(TRIM(description))                        AS description,

        CASE
            WHEN quantity ~ '^-?[0-9]+$'
            THEN quantity::INTEGER
            ELSE NULL
        END                                             AS quantity,

        -- Formato fuente: YYYY-MM-DD HH:MM:SS
        CASE
            WHEN invoice_date ~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
            THEN TO_TIMESTAMP(invoice_date, 'YYYY-MM-DD HH24:MI:SS') AT TIME ZONE 'UTC'
            ELSE NULL
        END                                             AS invoice_date_utc,

        CASE
            WHEN price ~ '^[0-9]*\.?[0-9]+$'
            THEN price::NUMERIC(10, 2)
            ELSE NULL
        END                                             AS unit_price,

        COALESCE(NULLIF(TRIM(customer_id), ''), 'GUEST') AS customer_id,
        UPPER(TRIM(country))                            AS country,

        CASE
            WHEN UPPER(TRIM(invoice)) LIKE 'C%' THEN 'DEVOLUCION'
            WHEN quantity ~ '^-?[0-9]+$' AND quantity::INTEGER <= 0 THEN 'DEVOLUCION'
            ELSE 'VENTA'
        END                                             AS transaction_type,

        'online_retail_ii'                              AS source_file

    FROM source
    WHERE invoice IS NOT NULL
      AND stock_code IS NOT NULL
)

SELECT * FROM cleaned
