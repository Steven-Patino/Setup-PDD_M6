-- =============================================================================
-- Dimensión: dim_cliente
-- =============================================================================
-- Incluye todos los clientes identificados MÁS el cliente 'GUEST'.
-- Decisión documentada: las transacciones sin CustomerID se asignan a 'GUEST'
-- para no perder el volumen de ventas. Se puede filtrar en los análisis.
-- =============================================================================

{{ config(materialized='table', schema='marts') }}

SELECT
    MD5(customer_id)    AS cliente_key,
    customer_id,
    CASE
        WHEN customer_id = 'GUEST' THEN false
        ELSE true
    END                 AS es_cliente_identificado
FROM (
    SELECT DISTINCT customer_id
    FROM {{ ref('stg_transactions_unified') }}
    WHERE customer_id IS NOT NULL
) clientes
