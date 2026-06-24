# Decisiones tecnicas del modelo dbt

## Clientes sin identificador
Se conservan como `GUEST` para no perder volumen y poder comparar comportamiento entre clientes identificados y anonimos.

## Descripcion canonica
Para `dim_producto` se usa la descripcion normalizada mas frecuente por codigo de producto. Si hay empate, se prefiere la descripcion mas larga y luego la alfabetica.

## Duplicados entre fuentes
Se deduplican por `(invoice_no, stock_code, fecha truncada al minuto)` y se da prioridad a `ecommerce_data`.

## Categorias
No se usa la API opcional. La categoria se asigna con reglas de palabras clave sobre la descripcion canonica.

## Devoluciones y ajustes
Toda transaccion con `quantity <= 0` se clasifica como `DEVOLUCION` en staging para separar ventas y devoluciones en los facts.
