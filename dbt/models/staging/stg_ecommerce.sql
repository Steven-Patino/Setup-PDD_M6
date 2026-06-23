-- =============================================================================
-- Modelo: stg_ecommerce
-- Fuente: raw.ecommerce_data (data.csv — Fuente 1: Kaggle ecommerce-data)
-- Capa:   Staging → VIEW (sin almacenamiento, siempre actualizada)
-- =============================================================================
-- Responsabilidad:
--   1. Castear tipos de dato correctamente
--   2. Normalizar product codes (MAYÚSCULAS, sin espacios)
--   3. Normalizar descripciones a MAYÚSCULAS (decisión de nombre canónico)
--   4. Estandarizar fechas a UTC
--   5. Rellenar CustomerID nulo con 'GUEST'
--   6. Clasificar cada registro como VENTA o DEVOLUCION
--
-- Decisiones técnicas documentadas en docs/decisiones_tecnicas.md
-- =============================================================================

{{ config(materialized='view') }}

WITH source AS (
    SELECT * FROM {{ source('raw', 'ecommerce_data') }}
),

cleaned AS (
    SELECT
        -- Normalizar código de factura
        UPPER(TRIM(invoice_no))                         AS invoice_no,

        -- Normalizar código de producto: mayúsculas y sin espacios
        UPPER(TRIM(stock_code))                         AS stock_code,

        -- Descripción canónica: MAYÚSCULAS para todo (estandarización simple y consistente)
        UPPER(TRIM(description))                        AS description,

        -- Cantidad: castear a INTEGER, NULL si no es un número válido
        CASE
            WHEN quantity ~ '^-?[0-9]+$'
            THEN quantity::INTEGER
            ELSE NULL
        END                                             AS quantity,

        -- Fecha a UTC. Formato fuente: M/D/YYYY H:MM
        CASE
            WHEN invoice_date ~ '^\d{1,2}/\d{1,2}/\d{4} \d{1,2}:\d{2}$'
            THEN TO_TIMESTAMP(invoice_date, 'MM/DD/YYYY HH24:MI') AT TIME ZONE 'UTC'
            ELSE NULL
        END                                             AS invoice_date_utc,

        -- Precio: castear a NUMERIC, NULL si no es válido
        CASE
            WHEN unit_price ~ '^[0-9]*\.?[0-9]+$'
            THEN unit_price::NUMERIC(10, 2)
            ELSE NULL
        END                                             AS unit_price,

        -- CustomerID: NULL → 'GUEST' (ver decisión en docs/)
        COALESCE(NULLIF(TRIM(customer_id), ''), 'GUEST') AS customer_id,

        UPPER(TRIM(country))                            AS country,

        -- Clasificación: DEVOLUCION si la factura tiene prefijo C o la cantidad es negativa
        CASE
            WHEN UPPER(TRIM(invoice_no)) LIKE 'C%' THEN 'DEVOLUCION'
            WHEN quantity ~ '^-?[0-9]+$' AND quantity::INTEGER <= 0 THEN 'DEVOLUCION'
            ELSE 'VENTA'
        END                                             AS transaction_type,

        'ecommerce_data'                                AS source_file

    FROM source
    WHERE invoice_no IS NOT NULL
      AND stock_code IS NOT NULL
)

SELECT * FROM cleaned
