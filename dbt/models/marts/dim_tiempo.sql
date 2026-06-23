-- =============================================================================
-- Dimensión: dim_tiempo
-- =============================================================================
-- Genera una fila por cada fecha DISTINTA que aparece en las transacciones.
-- Incluye atributos de calendario para facilitar análisis por periodo.
-- =============================================================================

{{ config(materialized='table', schema='marts') }}

SELECT
    fecha::TEXT                                     AS tiempo_key,
    fecha,
    EXTRACT(YEAR  FROM fecha)::INTEGER              AS anio,
    EXTRACT(MONTH FROM fecha)::INTEGER              AS mes,
    EXTRACT(DAY   FROM fecha)::INTEGER              AS dia,
    EXTRACT(QUARTER FROM fecha)::INTEGER            AS trimestre,
    TO_CHAR(fecha, 'YYYY-MM')                       AS anio_mes,
    TO_CHAR(fecha, 'Month')                         AS nombre_mes
FROM (
    SELECT DISTINCT invoice_date_utc::DATE AS fecha
    FROM {{ ref('stg_transactions_unified') }}
    WHERE invoice_date_utc IS NOT NULL
) fechas
ORDER BY fecha
