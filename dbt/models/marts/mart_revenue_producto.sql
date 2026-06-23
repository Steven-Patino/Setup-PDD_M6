-- =============================================================================
-- Mart: mart_revenue_producto
-- =============================================================================
-- Tabla analítica pre-agregada por producto, categoría, país y día.
-- Responde directamente las preguntas de negocio del examen:
--   Q1: Evolución mensual de ventas netas
--   Q2: Revenue bruto y tasa de devolución por categoría
--   Q3: Top 10 productos por revenue neto / tasa de devolución
--   Q4: Países con más transacciones y ticket promedio
-- =============================================================================

{{ config(materialized='table', schema='marts') }}

WITH ventas_por_dia AS (
    SELECT
        fv.producto_key,
        fv.tiempo_key,
        fv.pais_key,
        SUM(fv.cantidad)        AS cantidad_vendida,
        SUM(fv.revenue_bruto)   AS revenue_ventas,
        COUNT(DISTINCT fv.invoice_no) AS num_facturas
    FROM {{ ref('fact_ventas') }} fv
    GROUP BY fv.producto_key, fv.tiempo_key, fv.pais_key
),

devoluciones_por_dia AS (
    SELECT
        fd.producto_key,
        fd.tiempo_key,
        fd.pais_key,
        SUM(fd.cantidad_devuelta)    AS cantidad_devuelta,
        SUM(fd.revenue_devolucion)   AS revenue_devoluciones
    FROM {{ ref('fact_devoluciones') }} fd
    GROUP BY fd.producto_key, fd.tiempo_key, fd.pais_key
)

SELECT
    -- Claves y atributos descriptivos
    p.codigo_producto,
    p.nombre_canonico,
    p.categoria,
    t.fecha,
    t.anio_mes,
    t.anio,
    t.mes,
    t.trimestre,
    pa.nombre_pais,

    -- Métricas de ventas
    COALESCE(v.cantidad_vendida, 0)     AS cantidad_vendida,
    COALESCE(v.revenue_ventas, 0)       AS revenue_ventas,
    COALESCE(v.num_facturas, 0)         AS num_facturas,

    -- Métricas de devoluciones
    COALESCE(d.cantidad_devuelta, 0)    AS cantidad_devuelta,
    COALESCE(d.revenue_devoluciones, 0) AS revenue_devoluciones,

    -- Revenue neto = ventas - devoluciones (regla de negocio central)
    COALESCE(v.revenue_ventas, 0) - COALESCE(d.revenue_devoluciones, 0) AS revenue_neto,

    -- Tasa de devolución (0 a 1, 0 si no hubo ventas)
    CASE
        WHEN COALESCE(v.cantidad_vendida, 0) = 0 THEN 0
        ELSE ROUND(
            COALESCE(d.cantidad_devuelta, 0)::NUMERIC /
            COALESCE(v.cantidad_vendida, 0)::NUMERIC,
            4
        )
    END                                 AS tasa_devolucion,

    -- Ticket promedio por factura
    CASE
        WHEN COALESCE(v.num_facturas, 0) = 0 THEN 0
        ELSE ROUND(
            COALESCE(v.revenue_ventas, 0) / COALESCE(v.num_facturas, 0),
            2
        )
    END                                 AS ticket_promedio

FROM {{ ref('dim_producto') }} p

-- CROSS JOIN entre producto y tiempo para tener todas las combinaciones relevantes
-- Usamos INNER JOIN para solo tener filas con actividad real
INNER JOIN ventas_por_dia v       ON p.producto_key = v.producto_key
INNER JOIN {{ ref('dim_tiempo') }} t ON v.tiempo_key = t.tiempo_key
INNER JOIN {{ ref('dim_pais') }} pa  ON v.pais_key = pa.pais_key
LEFT  JOIN devoluciones_por_dia d ON p.producto_key = d.producto_key
                                  AND v.tiempo_key = d.tiempo_key
                                  AND v.pais_key = d.pais_key
