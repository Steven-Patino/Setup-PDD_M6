-- =============================================================================
-- Modelo: stg_ecommerce
-- Fuente: raw.ecommerce_data
-- Capa:   Staging -> VIEW
-- =============================================================================
-- Decision: esta capa solo limpia y normaliza. No excluye transacciones por
-- negocio; eso se controla en stg_transactions_unified y en los facts.
-- =============================================================================

{{ config(materialized='view') }}

WITH source AS (
    SELECT
        invoice_no   AS raw_invoice_no,
        stock_code   AS raw_stock_code,
        description  AS raw_description,
        quantity     AS raw_quantity,
        invoice_date AS raw_invoice_date,
        unit_price   AS raw_unit_price,
        customer_id  AS raw_customer_id,
        country      AS raw_country
    FROM {{ source('raw', 'ecommerce_data') }}
),

typed AS (
    SELECT
        {{ normalize_code('raw_invoice_no') }}       AS invoice_no,
        {{ normalize_code('raw_stock_code') }}       AS stock_code,
        {{ normalize_description('raw_description') }} AS description,
        {{ safe_integer('raw_quantity') }}           AS quantity,
        CASE
            WHEN NULLIF(BTRIM(raw_invoice_date), '') IS NULL THEN NULL
            WHEN BTRIM(raw_invoice_date) ~ '^\d{1,2}/\d{1,2}/\d{4} \d{1,2}:\d{2}$'
                THEN (TO_TIMESTAMP(BTRIM(raw_invoice_date), 'MM/DD/YYYY HH24:MI') AT TIME ZONE 'UTC')
            ELSE NULL
        END                                          AS invoice_date_utc,
        {{ safe_numeric('raw_unit_price') }}         AS unit_price,
        COALESCE(NULLIF(BTRIM(raw_customer_id), ''), 'GUEST') AS customer_id,
        UPPER(REGEXP_REPLACE(BTRIM(CAST(raw_country AS TEXT)), '\s+', ' ', 'g')) AS country,
        'ecommerce_data'                             AS source_file
    FROM source
    WHERE NULLIF(BTRIM(raw_invoice_no), '') IS NOT NULL
      AND NULLIF(BTRIM(raw_stock_code), '') IS NOT NULL
),

cleaned AS (
    SELECT
        *,
        CASE
            WHEN quantity IS NULL THEN NULL
            WHEN quantity <= 0 THEN 'DEVOLUCION'
            ELSE 'VENTA'
        END AS transaction_type
    FROM typed
)

SELECT
    invoice_no,
    stock_code,
    description,
    quantity,
    invoice_date_utc,
    unit_price,
    customer_id,
    country,
    transaction_type,
    source_file
FROM cleaned
