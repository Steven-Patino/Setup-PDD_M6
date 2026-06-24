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
