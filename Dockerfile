# Imagen base oficial de Airflow. Actualizada a la última versión estable (3.2.2).
FROM apache/airflow:3.2.2

# Paso 1: Instalar dependencias del sistema como root
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends git \
    && apt-get autoremove -yqq --purge \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Paso 2: Volver al usuario airflow para instalar paquetes Python de forma segura
USER airflow

# Copiamos requirements ANTES del resto del proyecto para aprovechar la caché de capas de Docker:
# si requirements.txt no cambia, esta capa no se reconstruye.
COPY requirements.txt /requirements.txt

# Corregido: Se añade el flag '--user' para asegurar que se instale en el entorno del usuario airflow
# sin pisar ni romper las librerías nativas del core de Airflow.
RUN pip install --no-cache-dir --user -r /requirements.txt