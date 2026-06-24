-- =============================================================================
-- Mart: mart_revenue_producto
-- =============================================================================
-- Mart analitico a nivel producto-fecha-pais.
-- Usa FULL OUTER JOIN para conservar productos que solo tengan devoluciones.
-- =============================================================================

{{ config(materialized='table', schema='marts') }}

WITH ventas_por_dia AS (
    SELECT
        producto_key,
        tiempo_key,
        pais_key,
        SUM(cantidad)            AS cantidad_vendida,
        SUM(revenue_bruto)       AS revenue_ventas,
        COUNT(DISTINCT invoice_no) AS num_facturas
    FROM {{ ref('fact_ventas') }}
    GROUP BY 1, 2, 3
),

devoluciones_por_dia AS (
    SELECT
        producto_key,
        tiempo_key,
        pais_key,
        SUM(cantidad_devuelta)   AS cantidad_devuelta,
        SUM(revenue_devolucion)  AS revenue_devoluciones
    FROM {{ ref('fact_devoluciones') }}
    GROUP BY 1, 2, 3
),

base AS (
    SELECT
        COALESCE(v.producto_key, d.producto_key) AS producto_key,
        COALESCE(v.tiempo_key, d.tiempo_key)     AS tiempo_key,
        COALESCE(v.pais_key, d.pais_key)         AS pais_key,
        COALESCE(v.cantidad_vendida, 0)          AS cantidad_vendida,
        COALESCE(v.revenue_ventas, 0)            AS revenue_ventas,
        COALESCE(v.num_facturas, 0)              AS num_facturas,
        COALESCE(d.cantidad_devuelta, 0)         AS cantidad_devuelta,
        COALESCE(d.revenue_devoluciones, 0)      AS revenue_devoluciones
    FROM ventas_por_dia v
    FULL OUTER JOIN devoluciones_por_dia d
        ON v.producto_key = d.producto_key
       AND v.tiempo_key = d.tiempo_key
       AND v.pais_key = d.pais_key
)

SELECT
    p.codigo_producto,
    p.nombre_canonico,
    p.categoria,
    t.fecha,
    t.anio_mes,
    t.anio,
    t.mes,
    t.trimestre,
    pa.nombre_pais,
    b.cantidad_vendida,
    b.revenue_ventas,
    b.num_facturas,
    b.cantidad_devuelta,
    b.revenue_devoluciones,
    b.revenue_ventas - b.revenue_devoluciones AS revenue_neto,
    CASE
        WHEN b.cantidad_vendida = 0 THEN 0
        ELSE ROUND(b.cantidad_devuelta::NUMERIC / b.cantidad_vendida::NUMERIC, 4)
    END AS tasa_devolucion,
    CASE
        WHEN b.num_facturas = 0 THEN 0
        ELSE ROUND(b.revenue_ventas / b.num_facturas, 2)
    END AS ticket_promedio
FROM base b
JOIN {{ ref('dim_producto') }} p
  ON b.producto_key = p.producto_key
JOIN {{ ref('dim_tiempo') }} t
  ON b.tiempo_key = t.tiempo_key
JOIN {{ ref('dim_pais') }} pa
  ON b.pais_key = pa.pais_key
