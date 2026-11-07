FROM apache/airflow:3.1.0-python3.12

COPY requirements.txt /requirements.txt

RUN python -m venv /opt/airflow/dbt_venv \
    && /opt/airflow/dbt_venv/bin/pip install --no-cache-dir -r /requirements.txt

ENV DBT_VENV_PATH=/opt/airflow/dbt_venv
ENV PATH=/opt/airflow/dbt_venv/bin:$PATH