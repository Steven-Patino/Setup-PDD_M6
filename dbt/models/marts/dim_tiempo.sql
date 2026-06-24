-- =============================================================================
-- Dimensión: dim_tiempo
-- =============================================================================
-- Una fila por fecha distinta presente en transacciones. Se guarda como DATE
-- ya normalizada a UTC en staging.
-- =============================================================================

{{ config(
    materialized='table',
    schema='marts',
    post_hook=["ALTER TABLE \"{{ target.database }}\".\"marts\".\"dim_tiempo\" ADD CONSTRAINT pk_dim_tiempo PRIMARY KEY (tiempo_key)"]
) }}

WITH fechas AS (
    SELECT DISTINCT
        invoice_date_utc::DATE AS fecha
    FROM {{ ref('stg_transactions_unified') }}
    WHERE invoice_date_utc IS NOT NULL
)

SELECT
    fecha::TEXT                           AS tiempo_key,
    fecha,
    EXTRACT(YEAR FROM fecha)::INTEGER     AS anio,
    EXTRACT(MONTH FROM fecha)::INTEGER    AS mes,
    EXTRACT(DAY FROM fecha)::INTEGER      AS dia,
    EXTRACT(QUARTER FROM fecha)::INTEGER  AS trimestre,
    TO_CHAR(fecha, 'YYYY-MM')             AS anio_mes,
    TO_CHAR(fecha, 'TMMonth')             AS nombre_mes
FROM fechas
ORDER BY fecha
