-- =============================================================================
-- Modelo: stg_source_data
-- Capa:   Staging (materialización: VIEW — ver dbt_project.yml)
-- =============================================================================
-- Responsabilidad: UNA SOLA transformación por modelo.
-- Este modelo limpia y estandariza los datos crudos sin agregar ni unir nada.
-- Las decisiones de negocio van en la capa de marts.
--
-- Para adaptar al proyecto real:
--   1. Cambiar 'your_source_table' en schema.yml por el nombre de tu tabla
--   2. Ajustar los castings de tipos según tu esquema real
--   3. Agregar o quitar columnas según necesites
-- =============================================================================

{{ config(materialized='view') }}

SELECT
    -- Clave primaria: cast explícito para garantizar el tipo correcto
    id::INTEGER                                 AS id,

    -- Texto: eliminar espacios y normalizar a minúsculas
    TRIM(LOWER(nombre::TEXT))                   AS nombre,

    -- Numérico: reemplazar nulos por 0 para evitar problemas en agregaciones
    COALESCE(valor::NUMERIC(12, 2), 0)          AS valor,

    -- Categoría: cast explícito + limite de longitud
    categoria::VARCHAR(100)                     AS categoria,

    -- Fecha: truncar a DATE para consistencia (eliminar componente horario)
    fecha_registro::DATE                        AS fecha_registro,

    -- Columna de auditoría: cuándo procesó dbt este registro
    CURRENT_TIMESTAMP                           AS _procesado_en

FROM {{ source('raw', 'your_source_table') }}

-- Filtro de calidad: descartar registros sin ID (datos inválidos en origen)
WHERE id IS NOT NULL
