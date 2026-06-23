# Documento de Decisiones Técnicas
## Pipeline ETL/ELT — DataMart S.A.S.

---

## 1. Diseño del Modelo del Repositorio Analítico

### Arquitectura de capas

Se eligió una arquitectura de tres capas (Medallion Architecture) implementada con tres schemas en PostgreSQL:

| Schema | Qué contiene | Materialización |
|---|---|---|
| `raw` | Datos tal como llegan de los CSV, sin transformar | Tablas creadas por el DAG (Python) |
| `staging` | Datos limpios y tipados, sin lógica de negocio | VIEWS en dbt |
| `marts` | Star Schema para análisis — tablas de hechos y dimensiones | TABLES en dbt |

**Por qué staging es VIEW y no TABLE:** las vistas no consumen espacio de almacenamiento y siempre reflejan el estado actual de los datos raw. Como el pipeline hace TRUNCATE + INSERT en raw, las vistas se actualizan automáticamente sin necesidad de reprocesarlas explícitamente.

**Por qué marts son TABLE:** las consultas analíticas necesitan rendimiento. Las tablas materializadas permiten agregar índices y son más rápidas que recalcular desde staging en cada consulta.

### Modelo estrella (Star Schema)

```
                   ┌──────────────────┐
                   │   dim_tiempo     │
                   │ tiempo_key (PK)  │
                   │ fecha, anio, mes │
                   │ trimestre, etc.  │
                   └────────┬─────────┘
                            │
┌──────────────┐   ┌────────┴─────────┐   ┌──────────────────┐
│ dim_producto │   │   fact_ventas    │   │   dim_cliente    │
│producto_key  ├───┤ producto_key(FK) ├───┤ cliente_key (PK) │
│codigo_product│   │ cliente_key (FK) │   │ customer_id      │
│nombre_canonic│   │ tiempo_key (FK)  │   │ es_identificado  │
│categoria     │   │ pais_key (FK)    │   └──────────────────┘
└──────────────┘   │ cantidad         │
                   │ unit_price       │
┌──────────────┐   │ revenue_bruto    │   ┌──────────────────┐
│  dim_pais    │   └──────────────────┘   │fact_devoluciones │
│ pais_key(PK) │                          │ (misma estructura│
│ nombre_pais  │   mart_revenue_producto  │  que fact_ventas)│
└──────────────┘   (tabla pre-agregada)   └──────────────────┘
```

Se separaron ventas y devoluciones en dos fact tables distintas porque:
- Es una regla de negocio explícita del examen
- Permite calcular el revenue_neto como una resta limpia
- Facilita analizar el comportamiento de devoluciones de forma independiente

La tabla `mart_revenue_producto` es un mart pre-agregado (no es una fact table del esquema estrella) que responde directamente las preguntas de negocio.

---

## 2. Resolución de Casos Ambiguos

### 2.1 Transacciones sin CustomerID

**Decisión: Se incluyen, asignándoles el CustomerID = 'GUEST'**

**Justificación:** excluirlas significaría perder una parte real del volumen de ventas. El negocio necesita conocer el revenue total para sus reportes financieros. Un cliente anónimo sigue generando ingresos.

**Impacto documentado:** la dimensión `dim_cliente` tiene la columna `es_cliente_identificado` (true/false) que permite filtrar fácilmente. La pregunta de negocio Q5 se puede responder con este flag.

**Alternativa descartada:** asignar un ID numérico negativo o NULL. Se descartó porque complica los joins y los filtros en los modelos.

---

### 2.2 Descripciones inconsistentes del mismo producto

**Decisión: Se usa la descripción más frecuente como nombre canónico, normalizada a MAYÚSCULAS**

Ejemplos en los datos:
- `ALARM CLOCK BAKELIKE PINK` (aparece 3 veces)
- `alarm clock bakelike pink` (aparece 1 vez)
- `Alarm Clock Bakelike Pink` (aparece 1 vez)

**Implementación:** el modelo `dim_producto.sql` hace un `COUNT(*)` de cada variante por stock_code y usa `DISTINCT ON (stock_code) ORDER BY frecuencia DESC` para quedarse con la más frecuente. Luego la normaliza a MAYÚSCULAS para consistencia absoluta.

**Por qué MAYÚSCULAS:** es la forma original del sistema legado y la más frecuente en los datos. También facilita comparaciones case-insensitive sin usar funciones.

---

### 2.3 Duplicados entre las dos fuentes de Kaggle

**Decisión: Prioridad a la Fuente 1 (ecommerce_data / data.csv)**

**Justificación:** el enunciado del examen describe data.csv como "el volcado diario de órdenes del sistema operacional", es decir, la fuente de verdad más reciente. online_retail_II.csv es el "historial histórico" que se carga una sola vez.

**Implementación técnica:** el modelo `stg_transactions_unified.sql` asigna `source_priority = 1` a ecommerce_data y `source_priority = 2` a online_retail_ii. Luego usa `ROW_NUMBER() OVER (PARTITION BY invoice_no, stock_code, DATE_TRUNC('minute', invoice_date_utc) ORDER BY source_priority)` y se queda solo con `rn = 1`.

La clave de deduplicación es `(invoice_no, stock_code, fecha_truncada_al_minuto)` porque:
- `invoice_no + stock_code` identifica una línea de factura
- El truncado al minuto tolera pequeñas diferencias de segundos entre fuentes

---

### 2.4 Transacciones con precio = 0 o negativo en ventas

**Decisión: Se rechazan y se registran en `raw.rejected_records` con el motivo**

Las devoluciones (invoice con prefijo 'C') sí pueden tener precio como referencia; no se rechazan.

**Registros encontrados en los datos de muestra:**
- `DOTCOM POSTAGE` con precio 0.00 — posiblemente un cargo de prueba
- `Manual` con precio 0.00 y cantidad -1 — ajuste contable sin valor económico
- `INVALID ZERO PRICE ITEM` — dato inválido

**Motivo registrado en rejected_records:** `"unit_price <= 0 en una venta"`

---

### 2.5 Códigos de producto no estándar (letras)

**Decisión: Se cargan y se procesan como cualquier otro producto**

Ejemplos: `POST` (postage), `DOT` (dotcom postage), `M` (manual), `BAD001`.

**Justificación:** el examen no prohíbe estos códigos explícitamente. Filtrarlos sin criterio claro podría eliminar cargos legítimos de envío (`POST`) que sí tienen valor económico. La regla de negocio oficial solo filtra por precio = 0, no por formato del código.

**Normalización aplicada:** UPPER(TRIM(stock_code)) en todos los modelos de staging.

---

## 3. Garantía de Idempotencia del DAG

El DAG es idempotente: ejecutarlo dos veces el mismo día con los mismos datos produce exactamente el mismo resultado.

### Capa raw (Python)
Antes de cada carga se ejecuta `TRUNCATE TABLE raw.ecommerce_data` y `TRUNCATE TABLE raw.online_retail_ii`. Si el DAG falla a mitad de la carga y se reintenta, la tabla queda vacía y se recarga desde el inicio. No hay duplicados posibles.

### Capa staging (dbt)
Los modelos de staging son VIEWS. Cada vez que se consultan, reflejan el estado actual de las tablas raw. No hay estado que persista entre ejecuciones.

### Capa marts (dbt)
Los modelos con `materialized='table'` en dbt usan internamente una transacción que:
1. Crea una tabla temporal con los nuevos datos
2. La renombra reemplazando la tabla anterior (DROP + RENAME atómico)

El resultado final es siempre idéntico si los datos de entrada son los mismos.

### Claves surrogadas (MD5)
Las claves surrogadas en las dimensiones se calculan con `MD5(codigo)`. Al ser deterministas, el mismo código produce siempre la misma clave. Esto garantiza que los joins entre fact y dim funcionen correctamente en cualquier ejecución.

---

## 4. Asignación de Categorías (sin API)

Como el plus de la API REST es opcional y no se implementó, las categorías se asignan por palabras clave en la descripción del producto dentro del modelo `dim_producto.sql`:

| Palabras clave en descripción | Categoría asignada |
|---|---|
| LIGHT, LAMP, GLASS BALL, CANDLE | Iluminacion |
| BAG, LUNCH | Accesorios |
| CLOCK, FRAME, SEWING, BUILDING BLOCK, BOX | Hogar |
| WARMER, ORNAMENT, BIRD, HEART | Decoracion |
| POSTAGE, DOTCOM, MANUAL | Logistica |
| (ninguna coincidencia) | General |

Esta estrategia es simple, consistente y no requiere datos externos. Sus limitaciones son conocidas (puede haber errores para productos con nombres poco descriptivos) y están documentadas aquí.
