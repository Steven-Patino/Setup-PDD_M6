-- =============================================================================
-- Modelo: stg_transactions_unified
-- Capa:   Staging → VIEW
-- =============================================================================
-- Unifica las dos fuentes de datos en un único conjunto de transacciones.
--
-- Decisión sobre duplicados entre fuentes:
--   Los datasets se solapan en el periodo 2010-2011. Para detectar duplicados
--   se usa la clave compuesta: (invoice_no, stock_code, fecha truncada al minuto).
--   En caso de duplicado, se prioriza la Fuente 1 (ecommerce_data) porque es
--   el "volcado diario oficial" del sistema operacional de DataMart.
--
-- Decisión sobre registros rechazados:
--   - Precio = 0 o negativo en una VENTA → excluido de este modelo (va a raw.rejected_records)
--   - Cantidad NULL (no numérica) → excluido
--   - Fecha NULL (formato no reconocido) → excluido
--   Los registros excluidos se registran en raw.rejected_records por el DAG de Airflow.
-- =============================================================================

{{ config(materialized='view') }}

WITH fuente1 AS (
    SELECT
        *,
        1 AS source_priority  -- Fuente 1 tiene prioridad sobre duplicados
    FROM {{ ref('stg_ecommerce') }}
    -- Solo registros válidos: precio positivo en ventas, o devoluciones (precio puede ser ref)
    WHERE quantity IS NOT NULL
      AND invoice_date_utc IS NOT NULL
      AND (
            transaction_type = 'DEVOLUCION'
            OR (transaction_type = 'VENTA' AND unit_price > 0)
          )
),

fuente2 AS (
    SELECT
        *,
        2 AS source_priority  -- Fuente 2 es secundaria
    FROM {{ ref('stg_online_retail') }}
    WHERE quantity IS NOT NULL
      AND invoice_date_utc IS NOT NULL
      AND (
            transaction_type = 'DEVOLUCION'
            OR (transaction_type = 'VENTA' AND unit_price > 0)
          )
),

unificado AS (
    SELECT * FROM fuente1
    UNION ALL
    SELECT * FROM fuente2
),

-- Deduplicar: ante mismo (invoice_no, stock_code, minuto), quedarse con la de mayor prioridad
deduplicado AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY
                invoice_no,
                stock_code,
                DATE_TRUNC('minute', invoice_date_utc)
            ORDER BY source_priority ASC  -- 1 = ecommerce_data gana
        ) AS rn
    FROM unificado
)

SELECT
    -- Clave única de la transacción (MD5 es estable entre ejecuciones)
    MD5(
        invoice_no || '|' || stock_code || '|' ||
        invoice_date_utc::TEXT
    )                           AS transaction_key,

    invoice_no,
    stock_code,
    description,
    quantity,
    invoice_date_utc,
    unit_price,
    -- Revenue bruto: solo aplica para ventas; devoluciones tienen valor negativo
    quantity * unit_price       AS revenue_bruto,
    customer_id,
    country,
    transaction_type,
    source_file

FROM deduplicado
WHERE rn = 1
