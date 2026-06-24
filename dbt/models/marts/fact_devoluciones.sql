-- =============================================================================
-- Fact Table: fact_devoluciones
-- =============================================================================
-- Incluye devoluciones y ajustes (quantity <= 0). El valor se guarda en
-- positivo para facilitar el calculo de revenue neto en marts.
-- =============================================================================

{{ config(
    materialized='table',
    schema='marts',
    post_hook=[
        "ALTER TABLE \"{{ target.database }}\".\"marts\".\"fact_devoluciones\" ADD CONSTRAINT pk_fact_devoluciones PRIMARY KEY (transaction_key)",
        "ALTER TABLE \"{{ target.database }}\".\"marts\".\"fact_devoluciones\" ADD CONSTRAINT fk_fact_devoluciones_producto FOREIGN KEY (producto_key) REFERENCES \"{{ target.database }}\".\"marts\".\"dim_producto\" (producto_key)",
        "ALTER TABLE \"{{ target.database }}\".\"marts\".\"fact_devoluciones\" ADD CONSTRAINT fk_fact_devoluciones_cliente FOREIGN KEY (cliente_key) REFERENCES \"{{ target.database }}\".\"marts\".\"dim_cliente\" (cliente_key)",
        "ALTER TABLE \"{{ target.database }}\".\"marts\".\"fact_devoluciones\" ADD CONSTRAINT fk_fact_devoluciones_tiempo FOREIGN KEY (tiempo_key) REFERENCES \"{{ target.database }}\".\"marts\".\"dim_tiempo\" (tiempo_key)",
        "ALTER TABLE \"{{ target.database }}\".\"marts\".\"fact_devoluciones\" ADD CONSTRAINT fk_fact_devoluciones_pais FOREIGN KEY (pais_key) REFERENCES \"{{ target.database }}\".\"marts\".\"dim_pais\" (pais_key)"
    ]
) }}

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
