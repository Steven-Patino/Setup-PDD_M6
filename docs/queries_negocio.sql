-- =============================================================================
-- Consultas SQL de validación — Preguntas de negocio DataMart S.A.S.
-- Ejecutar contra la BD externa después de correr el pipeline completo.
-- Schema: marts (todas las tablas están en el schema marts)
-- =============================================================================


-- =============================================================================
-- Q1: ¿Cuál fue la evolución mensual de las ventas netas
--     (descontando devoluciones) durante el periodo cubierto por los datos?
-- =============================================================================
SELECT
    anio_mes,
    anio,
    mes,
    SUM(revenue_ventas)       AS total_revenue_ventas,
    SUM(revenue_devoluciones) AS total_devoluciones,
    SUM(revenue_neto)         AS total_revenue_neto,
    SUM(cantidad_vendida)     AS total_unidades_vendidas,
    SUM(num_facturas)         AS total_facturas
FROM marts.mart_revenue_producto
GROUP BY anio_mes, anio, mes
ORDER BY anio, mes;


-- =============================================================================
-- Q2: ¿Qué categorías generaron más revenue bruto
--     y cuáles tuvieron mayor proporción de devoluciones?
-- =============================================================================
SELECT
    categoria,
    SUM(revenue_ventas)                                  AS revenue_bruto_total,
    SUM(revenue_devoluciones)                            AS devoluciones_total,
    SUM(revenue_neto)                                    AS revenue_neto_total,
    ROUND(
        SUM(revenue_devoluciones) /
        NULLIF(SUM(revenue_ventas), 0) * 100,
        2
    )                                                    AS porcentaje_devolucion
FROM marts.mart_revenue_producto
GROUP BY categoria
ORDER BY revenue_bruto_total DESC;


-- =============================================================================
-- Q3a: ¿Cuáles son los 10 productos con mayor revenue neto?
-- =============================================================================
SELECT
    codigo_producto,
    nombre_canonico,
    categoria,
    SUM(revenue_neto)      AS revenue_neto_total,
    SUM(cantidad_vendida)  AS unidades_vendidas
FROM marts.mart_revenue_producto
GROUP BY codigo_producto, nombre_canonico, categoria
ORDER BY revenue_neto_total DESC
LIMIT 10;


-- =============================================================================
-- Q3b: ¿Cuáles son los 10 productos con mayor tasa de devolución?
-- (Solo productos con al menos 5 unidades vendidas para evitar sesgos)
-- =============================================================================
SELECT
    codigo_producto,
    nombre_canonico,
    categoria,
    SUM(cantidad_vendida)                                       AS unidades_vendidas,
    SUM(cantidad_devuelta)                                      AS unidades_devueltas,
    ROUND(
        SUM(cantidad_devuelta)::NUMERIC /
        NULLIF(SUM(cantidad_vendida), 0) * 100,
        2
    )                                                           AS tasa_devolucion_pct
FROM marts.mart_revenue_producto
GROUP BY codigo_producto, nombre_canonico, categoria
HAVING SUM(cantidad_vendida) >= 5
ORDER BY tasa_devolucion_pct DESC
LIMIT 10;


-- =============================================================================
-- Q4: ¿Qué países concentran la mayor parte de las transacciones
--     y cómo varía el ticket promedio entre ellos?
-- =============================================================================
SELECT
    nombre_pais,
    SUM(num_facturas)                                        AS total_facturas,
    SUM(cantidad_vendida)                                    AS total_unidades,
    SUM(revenue_ventas)                                      AS revenue_total,
    ROUND(
        SUM(revenue_ventas) / NULLIF(SUM(num_facturas), 0),
        2
    )                                                        AS ticket_promedio,
    ROUND(
        SUM(num_facturas)::NUMERIC /
        SUM(SUM(num_facturas)) OVER () * 100,
        2
    )                                                        AS pct_del_total
FROM marts.mart_revenue_producto
GROUP BY nombre_pais
ORDER BY total_facturas DESC;


-- =============================================================================
-- Q5: ¿Existe diferencia en el comportamiento entre clientes identificados
--     y transacciones sin CustomerID?
-- =============================================================================
SELECT
    dc.es_cliente_identificado,
    COUNT(DISTINCT fv.invoice_no)                AS num_facturas,
    SUM(fv.cantidad)                             AS total_unidades,
    SUM(fv.revenue_bruto)                        AS revenue_total,
    ROUND(
        SUM(fv.revenue_bruto) /
        NULLIF(COUNT(DISTINCT fv.invoice_no), 0),
        2
    )                                            AS ticket_promedio_por_factura,
    ROUND(
        SUM(fv.revenue_bruto) /
        NULLIF(SUM(fv.cantidad), 0),
        2
    )                                            AS precio_promedio_unitario
FROM marts.fact_ventas fv
JOIN marts.dim_cliente dc ON fv.cliente_key = dc.cliente_key
GROUP BY dc.es_cliente_identificado
ORDER BY dc.es_cliente_identificado DESC;


-- =============================================================================
-- Q6: ¿Qué productos aparecen en transacciones pero no tienen descripción
--     consistente? ¿Cuántos códigos únicos de producto existen en total?
-- =============================================================================

-- 6a: Conteo de códigos únicos de producto
SELECT COUNT(DISTINCT codigo_producto) AS total_codigos_unicos
FROM marts.dim_producto;

-- 6b: Productos con múltiples variantes de descripción en los datos crudos
-- (se ejecuta directamente contra el schema raw)
SELECT
    stock_code,
    COUNT(DISTINCT UPPER(TRIM(description))) AS variantes_descripcion,
    MIN(UPPER(TRIM(description)))            AS variante_1,
    MAX(UPPER(TRIM(description)))            AS variante_2
FROM raw.ecommerce_data
WHERE stock_code IS NOT NULL
GROUP BY stock_code
HAVING COUNT(DISTINCT UPPER(TRIM(description))) > 1
ORDER BY variantes_descripcion DESC;


-- =============================================================================
-- Q7: Recomendación concreta al equipo de producto
-- (Basada en los datos: productos con alto revenue pero también alta devolución)
-- =============================================================================
-- ¿Qué productos generan mucho revenue pero también muchas devoluciones?
-- Estos son candidatos a investigación de calidad.
SELECT
    codigo_producto,
    nombre_canonico,
    categoria,
    SUM(revenue_ventas)                                     AS revenue_bruto,
    SUM(revenue_devoluciones)                               AS devoluciones,
    SUM(revenue_neto)                                       AS revenue_neto,
    ROUND(
        SUM(revenue_devoluciones) /
        NULLIF(SUM(revenue_ventas), 0) * 100,
        2
    )                                                       AS tasa_devolucion_pct
FROM marts.mart_revenue_producto
GROUP BY codigo_producto, nombre_canonico, categoria
HAVING SUM(revenue_ventas) > 0
ORDER BY devoluciones DESC, revenue_bruto DESC
LIMIT 15;

-- =============================================================================
-- VALIDACIONES RÁPIDAS DE INTEGRIDAD
-- Para verificar que el pipeline cargó datos correctamente:
-- =============================================================================

-- Total de registros en cada tabla
SELECT 'raw.ecommerce_data'    AS tabla, COUNT(*) AS registros FROM raw.ecommerce_data
UNION ALL
SELECT 'raw.online_retail_ii'  AS tabla, COUNT(*) AS registros FROM raw.online_retail_ii
UNION ALL
SELECT 'raw.rejected_records'  AS tabla, COUNT(*) AS registros FROM raw.rejected_records
UNION ALL
SELECT 'marts.fact_ventas'     AS tabla, COUNT(*) AS registros FROM marts.fact_ventas
UNION ALL
SELECT 'marts.fact_devoluciones' AS tabla, COUNT(*) AS registros FROM marts.fact_devoluciones
UNION ALL
SELECT 'marts.dim_producto'    AS tabla, COUNT(*) AS registros FROM marts.dim_producto
UNION ALL
SELECT 'marts.dim_cliente'     AS tabla, COUNT(*) AS registros FROM marts.dim_cliente
ORDER BY tabla;
