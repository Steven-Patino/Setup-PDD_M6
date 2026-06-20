-- =============================================================================
-- Modelo: mart_summary
-- Capa:   Marts (materialización: TABLE — ver dbt_project.yml)
-- =============================================================================
-- Responsabilidad: producir la tabla analítica final que consumen BI y dashboards.
-- Referencia a staging usando {{ ref() }}: dbt resuelve el orden de ejecución
-- automáticamente (no necesitas hardcodear nombres de esquemas/tablas).
-- =============================================================================

{{ config(materialized='table') }}

SELECT
    categoria,

    -- Truncar fecha al primer día del mes para agrupar temporalmente
    DATE_TRUNC('month', fecha_registro)::DATE   AS mes,

    -- Métricas agregadas
    COUNT(*)                                    AS total_registros,
    SUM(valor)                                  AS valor_total,
    ROUND(AVG(valor), 2)                        AS valor_promedio,
    MIN(valor)                                  AS valor_minimo,
    MAX(valor)                                  AS valor_maximo

-- ref() en lugar de nombre directo: dbt construye el grafo de dependencias
-- y garantiza que stg_source_data exista antes de ejecutar este modelo.
FROM {{ ref('stg_source_data') }}

GROUP BY
    categoria,
    DATE_TRUNC('month', fecha_registro)

ORDER BY
    mes DESC,
    categoria ASC
