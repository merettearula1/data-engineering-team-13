FROM apache/airflow:3.1.0-python3.12

USER airflow

# dbt lives in its own venv to avoid dependency conflicts with Airflow
RUN python -m venv /home/airflow/dbt_venv \
 && /home/airflow/dbt_venv/bin/pip install --no-cache-dir dbt-postgres==1.9.0

# Python libraries your ingestion tasks will need later (requests, etc.)
RUN pip install --no-cache-dir requests
