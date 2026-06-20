"""
DAG del Pipeline ETL/ELT con Airflow + dbt
============================================
Orquesta el proceso de transformación de datos sobre una BD PostgreSQL externa.

Flujo de tareas:
    [verificar_conexion] >> [dbt_run] >> [dbt_test] >> [dbt_docs]

Las tareas usan BashOperator para invocar la CLI de dbt, que está instalada
en la misma imagen de Airflow (ver Dockerfile y requirements.txt).
Las credenciales llegan al contenedor via variables de entorno desde .env,
y dbt/profiles.yml las lee con la función env_var().
"""

from __future__ import annotations

from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.bash import BashOperator

# Ruta donde está montado el proyecto dbt dentro del contenedor.
# Corresponde al volumen: ./dbt:/opt/airflow/dbt en docker-compose.yaml
DBT_DIR = "/opt/airflow/dbt"

# Flag para deshabilitar colores ANSI en los logs de Airflow (más legibles)
DBT_BASE_CMD = f"dbt --no-use-colors --project-dir {DBT_DIR} --profiles-dir {DBT_DIR}"

default_args = {
    "owner": "estudiante",
    "depends_on_past": False,
    "email_on_failure": False,
    "email_on_retry": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
}

with DAG(
    dag_id="pipeline_etl_dbt",
    default_args=default_args,
    description="Pipeline ETL/ELT: transformaciones con dbt sobre PostgreSQL externo",
    schedule="@daily",
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=["etl", "dbt", "postgres"],
    doc_md="""
## Pipeline ETL/ELT — Airflow + dbt

### Descripción
Este DAG orquesta las transformaciones de datos usando **dbt** sobre una
base de datos **PostgreSQL externa** (alojada en la nube).

### Requisitos previos
- Archivo `.env` configurado con las credenciales de la BD externa.
- Modelos dbt en `dbt/models/` apuntando a las tablas correctas.

### Tareas
| Tarea | Descripción |
|---|---|
| `verificar_conexion_bd` | `dbt debug` — valida conectividad y configuración |
| `dbt_run_transformaciones` | `dbt run` — ejecuta y materializa los modelos |
| `dbt_test_calidad` | `dbt test` — valida reglas de calidad de datos |
| `dbt_generar_documentacion` | `dbt docs generate` — actualiza el linaje de datos |
    """,
) as dag:

    # ------------------------------------------------------------------
    # Tarea 1: Verificar conexión
    # ------------------------------------------------------------------
    # dbt debug comprueba:
    #   - Que las credenciales en profiles.yml son correctas
    #   - Que el adaptador de PostgreSQL está instalado
    #   - Que el proyecto dbt es válido
    # Si esta tarea falla, las siguientes no se ejecutarán.
    # ------------------------------------------------------------------
    t1_verificar = BashOperator(
        task_id="verificar_conexion_bd",
        bash_command=f"{DBT_BASE_CMD} debug",
    )

    # ------------------------------------------------------------------
    # Tarea 2: Ejecutar modelos dbt
    # ------------------------------------------------------------------
    # dbt run compila el SQL de cada modelo en dbt/models/ y lo ejecuta
    # contra la BD externa, creando vistas o tablas según la configuración
    # de materialización de cada modelo.
    # ------------------------------------------------------------------
    t2_run = BashOperator(
        task_id="dbt_run_transformaciones",
        bash_command=f"{DBT_BASE_CMD} run",
    )

    # ------------------------------------------------------------------
    # Tarea 3: Ejecutar tests de calidad
    # ------------------------------------------------------------------
    # dbt test valida las reglas definidas en los archivos schema.yml:
    #   - not_null: ningún valor nulo en columnas críticas
    #   - unique: sin duplicados en claves primarias
    #   - accepted_values: valores dentro de un rango permitido
    # ------------------------------------------------------------------
    t3_test = BashOperator(
        task_id="dbt_test_calidad",
        bash_command=f"{DBT_BASE_CMD} test",
    )

    # ------------------------------------------------------------------
    # Tarea 4: Generar documentación
    # ------------------------------------------------------------------
    # Genera el grafo de linaje de datos (DAG de modelos) y la documentación
    # en dbt/target/. Para visualizarla: `dbt docs serve` (manual, fuera de Airflow).
    # ------------------------------------------------------------------
    t4_docs = BashOperator(
        task_id="dbt_generar_documentacion",
        bash_command=f"{DBT_BASE_CMD} docs generate",
    )

    # Dependencias en cadena lineal
    t1_verificar >> t2_run >> t3_test >> t4_docs
