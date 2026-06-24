-- =============================================================================
-- Fact Table: fact_ventas
-- =============================================================================
-- Solo ventas reales: quantity > 0 y unit_price > 0.
-- Cada fila conserva la relacion fisica hacia las dimensiones del star schema.
-- =============================================================================

{{ config(
    materialized='table',
    schema='marts',
    post_hook=[
        "ALTER TABLE \"{{ target.database }}\".\"marts\".\"fact_ventas\" ADD CONSTRAINT pk_fact_ventas PRIMARY KEY (transaction_key)",
        "ALTER TABLE \"{{ target.database }}\".\"marts\".\"fact_ventas\" ADD CONSTRAINT fk_fact_ventas_producto FOREIGN KEY (producto_key) REFERENCES \"{{ target.database }}\".\"marts\".\"dim_producto\" (producto_key)",
        "ALTER TABLE \"{{ target.database }}\".\"marts\".\"fact_ventas\" ADD CONSTRAINT fk_fact_ventas_cliente FOREIGN KEY (cliente_key) REFERENCES \"{{ target.database }}\".\"marts\".\"dim_cliente\" (cliente_key)",
        "ALTER TABLE \"{{ target.database }}\".\"marts\".\"fact_ventas\" ADD CONSTRAINT fk_fact_ventas_tiempo FOREIGN KEY (tiempo_key) REFERENCES \"{{ target.database }}\".\"marts\".\"dim_tiempo\" (tiempo_key)",
        "ALTER TABLE \"{{ target.database }}\".\"marts\".\"fact_ventas\" ADD CONSTRAINT fk_fact_ventas_pais FOREIGN KEY (pais_key) REFERENCES \"{{ target.database }}\".\"marts\".\"dim_pais\" (pais_key)"
    ]
) }}

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
