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
