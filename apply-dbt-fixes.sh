#!/usr/bin/env bash
# =============================================================================
# apply-dbt-fixes.sh
# Ejecutar UNA VEZ con: sudo bash apply-dbt-fixes.sh
#
# Qué hace:
#   1. Agrega pre_hook a todos los modelos de marts para que dbt pueda
#      reemplazar tablas sin fallar por "relation pk_X already exists".
#   2. Agrega dependencias explícitas de dimensiones en fact_ventas y
#      fact_devoluciones para garantizar orden de ejecución correcto.
#   3. Ajusta permisos del directorio dbt para que el usuario actual pueda
#      editar archivos en el futuro sin necesitar sudo.
# =============================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MARTS="$SCRIPT_DIR/dbt/models/marts"

echo "=== Aplicando fix de pre_hooks en modelos marts... ==="

# -----------------------------------------------------------------------------
# dim_pais.sql
# -----------------------------------------------------------------------------
cat > "$MARTS/dim_pais.sql" << 'SQLEOF'
-- =============================================================================
-- Dimensión: dim_pais
-- =============================================================================
-- Se normaliza a mayusculas y se conservan solo paises realmente presentes en
-- las transacciones limpias.
-- =============================================================================

{{ config(
    materialized='table',
    schema='marts',
    pre_hook=["ALTER TABLE IF EXISTS \"{{ target.database }}\".\"marts\".\"dim_pais\" DROP CONSTRAINT IF EXISTS pk_dim_pais"],
    post_hook=["ALTER TABLE \"{{ target.database }}\".\"marts\".\"dim_pais\" ADD CONSTRAINT pk_dim_pais PRIMARY KEY (pais_key)"]
) }}

WITH paises AS (
    SELECT DISTINCT
        country
    FROM {{ ref('stg_transactions_unified') }}
    WHERE country IS NOT NULL
      AND BTRIM(country) <> ''
)

SELECT
    MD5(country) AS pais_key,
    country      AS nombre_pais
FROM paises
SQLEOF

# -----------------------------------------------------------------------------
# dim_producto.sql
# -----------------------------------------------------------------------------
cat > "$MARTS/dim_producto.sql" << 'SQLEOF'
-- =============================================================================
-- Dimensión: dim_producto
-- =============================================================================
-- Canonico por codigo de producto:
--   - Se usa la descripcion normalizada mas frecuente.
--   - Si hay empate, se prefiere la descripcion mas larga y luego la alfabética.
-- Categoría:
--   - Estrategia sin API: clasificacion por palabras clave en la descripcion.
-- =============================================================================

{{ config(
    materialized='table',
    schema='marts',
    pre_hook=["ALTER TABLE IF EXISTS \"{{ target.database }}\".\"marts\".\"dim_producto\" DROP CONSTRAINT IF EXISTS pk_dim_producto"],
    post_hook=["ALTER TABLE \"{{ target.database }}\".\"marts\".\"dim_producto\" ADD CONSTRAINT pk_dim_producto PRIMARY KEY (producto_key)"]
) }}

WITH descripciones AS (
    SELECT
        stock_code,
        description,
        COUNT(*) AS frecuencia
    FROM {{ ref('stg_transactions_unified') }}
    WHERE stock_code IS NOT NULL
      AND description IS NOT NULL
    GROUP BY 1, 2
),

descripcion_canonica AS (
    SELECT DISTINCT ON (stock_code)
        stock_code,
        description AS nombre_canonico
    FROM descripciones
    ORDER BY
        stock_code,
        frecuencia DESC,
        LENGTH(description) DESC,
        description ASC
),

con_categoria AS (
    SELECT
        stock_code,
        nombre_canonico,
        CASE
            WHEN nombre_canonico LIKE '%LIGHT%'
              OR nombre_canonico LIKE '%LAMP%'
              OR nombre_canonico LIKE '%CANDLE%'
              OR nombre_canonico LIKE '%LANTERN%'
              OR nombre_canonico LIKE '%GLASS BALL%'
                THEN 'Iluminacion'
            WHEN nombre_canonico LIKE '%BAG%'
              OR nombre_canonico LIKE '%BASKET%'
              OR nombre_canonico LIKE '%LUNCH%'
                THEN 'Accesorios'
            WHEN nombre_canonico LIKE '%CLOCK%'
              OR nombre_canonico LIKE '%FRAME%'
              OR nombre_canonico LIKE '%BOX%'
              OR nombre_canonico LIKE '%SEWING%'
              OR nombre_canonico LIKE '%BUILDING BLOCK%'
                THEN 'Hogar'
            WHEN nombre_canonico LIKE '%HEART%'
              OR nombre_canonico LIKE '%ORNAMENT%'
              OR nombre_canonico LIKE '%BIRD%'
              OR nombre_canonico LIKE '%TREE%'
                THEN 'Decoracion'
            WHEN nombre_canonico LIKE '%POSTAGE%'
              OR nombre_canonico LIKE '%DOTCOM%'
              OR nombre_canonico LIKE '%MANUAL%'
                THEN 'Logistica'
            ELSE 'General'
        END AS categoria
    FROM descripcion_canonica
)

SELECT
    MD5(stock_code) AS producto_key,
    stock_code      AS codigo_producto,
    nombre_canonico,
    categoria
FROM con_categoria
SQLEOF

# -----------------------------------------------------------------------------
# dim_cliente.sql
# -----------------------------------------------------------------------------
cat > "$MARTS/dim_cliente.sql" << 'SQLEOF'
-- =============================================================================
-- Dimensión: dim_cliente
-- =============================================================================
-- Decision: los registros sin customer_id se conservan como GUEST para no
-- perder volumen de ventas. Eso permite comparar clientes identificados vs no
-- identificados sin romper el modelo dimensional.
-- =============================================================================

{{ config(
    materialized='table',
    schema='marts',
    pre_hook=["ALTER TABLE IF EXISTS \"{{ target.database }}\".\"marts\".\"dim_cliente\" DROP CONSTRAINT IF EXISTS pk_dim_cliente"],
    post_hook=["ALTER TABLE \"{{ target.database }}\".\"marts\".\"dim_cliente\" ADD CONSTRAINT pk_dim_cliente PRIMARY KEY (cliente_key)"]
) }}

WITH clientes AS (
    SELECT DISTINCT
        customer_id
    FROM {{ ref('stg_transactions_unified') }}
    WHERE customer_id IS NOT NULL
)

SELECT
    MD5(customer_id) AS cliente_key,
    customer_id,
    CASE
        WHEN customer_id = 'GUEST' THEN FALSE
        ELSE TRUE
    END AS es_cliente_identificado
FROM clientes
SQLEOF

# -----------------------------------------------------------------------------
# dim_tiempo.sql
# -----------------------------------------------------------------------------
cat > "$MARTS/dim_tiempo.sql" << 'SQLEOF'
-- =============================================================================
-- Dimensión: dim_tiempo
-- =============================================================================
-- Una fila por fecha distinta presente en transacciones. Se guarda como DATE
-- ya normalizada a UTC en staging.
-- =============================================================================

{{ config(
    materialized='table',
    schema='marts',
    pre_hook=["ALTER TABLE IF EXISTS \"{{ target.database }}\".\"marts\".\"dim_tiempo\" DROP CONSTRAINT IF EXISTS pk_dim_tiempo"],
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
SQLEOF

# -----------------------------------------------------------------------------
# fact_ventas.sql
# -----------------------------------------------------------------------------
cat > "$MARTS/fact_ventas.sql" << 'SQLEOF'
-- =============================================================================
-- Fact Table: fact_ventas
-- =============================================================================
-- Solo ventas reales: quantity > 0 y unit_price > 0.
-- Cada fila conserva la relacion fisica hacia las dimensiones del star schema.
--
-- Las dimensiones se declaran como dependencias explícitas mediante ref() para
-- garantizar que dbt las construya (y sus PKs queden disponibles) ANTES de
-- ejecutar los post_hooks con las FK de esta tabla.
-- =============================================================================

{{-
    config(
        materialized='table',
        schema='marts',
        pre_hook=[
            "ALTER TABLE IF EXISTS \"{{ target.database }}\".\"marts\".\"fact_ventas\" DROP CONSTRAINT IF EXISTS pk_fact_ventas",
            "ALTER TABLE IF EXISTS \"{{ target.database }}\".\"marts\".\"fact_ventas\" DROP CONSTRAINT IF EXISTS fk_fact_ventas_producto",
            "ALTER TABLE IF EXISTS \"{{ target.database }}\".\"marts\".\"fact_ventas\" DROP CONSTRAINT IF EXISTS fk_fact_ventas_cliente",
            "ALTER TABLE IF EXISTS \"{{ target.database }}\".\"marts\".\"fact_ventas\" DROP CONSTRAINT IF EXISTS fk_fact_ventas_tiempo",
            "ALTER TABLE IF EXISTS \"{{ target.database }}\".\"marts\".\"fact_ventas\" DROP CONSTRAINT IF EXISTS fk_fact_ventas_pais"
        ],
        post_hook=[
            "ALTER TABLE \"{{ target.database }}\".\"marts\".\"fact_ventas\" ADD CONSTRAINT pk_fact_ventas PRIMARY KEY (transaction_key)",
            "ALTER TABLE \"{{ target.database }}\".\"marts\".\"fact_ventas\" ADD CONSTRAINT fk_fact_ventas_producto FOREIGN KEY (producto_key) REFERENCES \"{{ target.database }}\".\"marts\".\"dim_producto\" (producto_key)",
            "ALTER TABLE \"{{ target.database }}\".\"marts\".\"fact_ventas\" ADD CONSTRAINT fk_fact_ventas_cliente  FOREIGN KEY (cliente_key)  REFERENCES \"{{ target.database }}\".\"marts\".\"dim_cliente\"  (cliente_key)",
            "ALTER TABLE \"{{ target.database }}\".\"marts\".\"fact_ventas\" ADD CONSTRAINT fk_fact_ventas_tiempo   FOREIGN KEY (tiempo_key)   REFERENCES \"{{ target.database }}\".\"marts\".\"dim_tiempo\"   (tiempo_key)",
            "ALTER TABLE \"{{ target.database }}\".\"marts\".\"fact_ventas\" ADD CONSTRAINT fk_fact_ventas_pais     FOREIGN KEY (pais_key)     REFERENCES \"{{ target.database }}\".\"marts\".\"dim_pais\"     (pais_key)"
        ]
    )
-}}

{#
  Dependencias explícitas en dimensiones: dbt no infiere la relación
  fact → dim cuando los surrogate keys se calculan con MD5() inline.
  Declararlas aquí garantiza que las dims (y sus PKs) existan antes de
  que los post_hooks intenten crear las FK de esta tabla.
#}
{% set _dim_deps = [
    ref('dim_producto'),
    ref('dim_cliente'),
    ref('dim_tiempo'),
    ref('dim_pais')
] %}

WITH ventas AS (
    SELECT
        *
    FROM {{ ref('stg_transactions_unified') }}
    WHERE transaction_type = 'VENTA'
      AND quantity > 0
      AND unit_price > 0
)

SELECT
    transaction_key,
    invoice_no,
    MD5(stock_code)               AS producto_key,
    MD5(customer_id)              AS cliente_key,
    invoice_date_utc::DATE::TEXT  AS tiempo_key,
    MD5(country)                  AS pais_key,
    quantity                      AS cantidad,
    unit_price,
    quantity * unit_price         AS revenue_bruto,
    invoice_date_utc,
    source_file
FROM ventas
SQLEOF

# -----------------------------------------------------------------------------
# fact_devoluciones.sql
# -----------------------------------------------------------------------------
cat > "$MARTS/fact_devoluciones.sql" << 'SQLEOF'
-- =============================================================================
-- Fact Table: fact_devoluciones
-- =============================================================================
-- Incluye devoluciones y ajustes (quantity <= 0). El valor se guarda en
-- positivo para facilitar el calculo de revenue neto en marts.
-- =============================================================================

{{-
    config(
        materialized='table',
        schema='marts',
        pre_hook=[
            "ALTER TABLE IF EXISTS \"{{ target.database }}\".\"marts\".\"fact_devoluciones\" DROP CONSTRAINT IF EXISTS pk_fact_devoluciones",
            "ALTER TABLE IF EXISTS \"{{ target.database }}\".\"marts\".\"fact_devoluciones\" DROP CONSTRAINT IF EXISTS fk_fact_devoluciones_producto",
            "ALTER TABLE IF EXISTS \"{{ target.database }}\".\"marts\".\"fact_devoluciones\" DROP CONSTRAINT IF EXISTS fk_fact_devoluciones_cliente",
            "ALTER TABLE IF EXISTS \"{{ target.database }}\".\"marts\".\"fact_devoluciones\" DROP CONSTRAINT IF EXISTS fk_fact_devoluciones_tiempo",
            "ALTER TABLE IF EXISTS \"{{ target.database }}\".\"marts\".\"fact_devoluciones\" DROP CONSTRAINT IF EXISTS fk_fact_devoluciones_pais"
        ],
        post_hook=[
            "ALTER TABLE \"{{ target.database }}\".\"marts\".\"fact_devoluciones\" ADD CONSTRAINT pk_fact_devoluciones PRIMARY KEY (transaction_key)",
            "ALTER TABLE \"{{ target.database }}\".\"marts\".\"fact_devoluciones\" ADD CONSTRAINT fk_fact_devoluciones_producto FOREIGN KEY (producto_key) REFERENCES \"{{ target.database }}\".\"marts\".\"dim_producto\" (producto_key)",
            "ALTER TABLE \"{{ target.database }}\".\"marts\".\"fact_devoluciones\" ADD CONSTRAINT fk_fact_devoluciones_cliente  FOREIGN KEY (cliente_key)  REFERENCES \"{{ target.database }}\".\"marts\".\"dim_cliente\"  (cliente_key)",
            "ALTER TABLE \"{{ target.database }}\".\"marts\".\"fact_devoluciones\" ADD CONSTRAINT fk_fact_devoluciones_tiempo   FOREIGN KEY (tiempo_key)   REFERENCES \"{{ target.database }}\".\"marts\".\"dim_tiempo\"   (tiempo_key)",
            "ALTER TABLE \"{{ target.database }}\".\"marts\".\"fact_devoluciones\" ADD CONSTRAINT fk_fact_devoluciones_pais     FOREIGN KEY (pais_key)     REFERENCES \"{{ target.database }}\".\"marts\".\"dim_pais\"     (pais_key)"
        ]
    )
-}}

{% set _dim_deps = [
    ref('dim_producto'),
    ref('dim_cliente'),
    ref('dim_tiempo'),
    ref('dim_pais')
] %}

WITH devoluciones AS (
    SELECT
        *
    FROM {{ ref('stg_transactions_unified') }}
    WHERE transaction_type = 'DEVOLUCION'
      AND quantity <= 0
)

SELECT
    transaction_key,
    invoice_no,
    MD5(stock_code)               AS producto_key,
    MD5(customer_id)              AS cliente_key,
    invoice_date_utc::DATE::TEXT  AS tiempo_key,
    MD5(country)                  AS pais_key,
    ABS(quantity)                 AS cantidad_devuelta,
    unit_price,
    ABS(quantity * unit_price)    AS revenue_devolucion,
    invoice_date_utc,
    source_file
FROM devoluciones
SQLEOF

echo "=== Ajustando permisos del directorio dbt para edición futura... ==="
# Hace los archivos dbt editables por cualquier usuario (entorno de desarrollo).
# El usuario airflow (50000) sigue pudiendo escribir; el usuario del host también.
find "$SCRIPT_DIR/dbt" -type d -exec chmod 777 {} \;
find "$SCRIPT_DIR/dbt" -type f -exec chmod 666 {} \;

echo ""
echo "=== Listo. Los cambios aplicados son: ==="
echo "  ✓ dim_pais.sql          — pre_hook DROP CONSTRAINT IF EXISTS pk_dim_pais"
echo "  ✓ dim_producto.sql      — pre_hook DROP CONSTRAINT IF EXISTS pk_dim_producto"
echo "  ✓ dim_cliente.sql       — pre_hook DROP CONSTRAINT IF EXISTS pk_dim_cliente"
echo "  ✓ dim_tiempo.sql        — pre_hook DROP CONSTRAINT IF EXISTS pk_dim_tiempo"
echo "  ✓ fact_ventas.sql       — pre_hooks + dependencias explícitas de dims"
echo "  ✓ fact_devoluciones.sql — pre_hooks + dependencias explícitas de dims"
echo "  ✓ dbt/                  — permisos 777/666 para edición libre"
echo ""
echo "Siguiente paso: triggear el DAG datamart_pipeline desde la UI (localhost:8080)"
