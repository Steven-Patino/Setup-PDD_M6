# Imagen base oficial de Airflow. Cambiar la versión aquí si se necesita otra.
FROM apache/airflow:2.9.3

# Paso 1: instalar dependencias del sistema como root
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends git \
    && apt-get autoremove -yqq --purge \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Paso 2: volver al usuario airflow para instalar paquetes Python de forma segura
USER airflow

# Copiamos requirements ANTES del resto del proyecto para aprovechar la caché de capas de Docker:
# si requirements.txt no cambia, esta capa no se reconstruye.
COPY requirements.txt /requirements.txt
RUN pip install --no-cache-dir -r /requirements.txt
