# Airflow handoff (task 2.4)

The existing DAG file is `data_warehouse/dags/tartu_transit_pipeline.py` and currently runs:

`resolve_date_range -> [ingest_weather, ingest_bus] -> dq_check_bronze -> dbt_run -> dbt_test`

That sequence does **not** run the `snap_stops` snapshot. Gold's `dim_stop` needs it.

Full DAG replacement is included **outside the direct copy overlay** at
`optional_airflow/tartu_transit_pipeline.py`.
Do NOT activate until `models/silver/` contains the required normalized models.

The proposed order is:

`resolve_date_range -> [ingest_weather, ingest_bus] -> dq_check_bronze -> dbt_run_silver -> dbt_snapshot_stops -> dbt_run_gold -> dbt_test`

The Airflow image's `Dockerfile` already installs `dbt-core==1.9.8` and `dbt-postgres==1.9.0` into a venv and adds it to PATH; `docker-compose.yml` mounts `./dbt` read-only under `/opt/airflow/dbt`. The dbt profile uses `WAREHOUSE_*` environment variables already set in Compose.

`dbt snapshot` writes to PostgreSQL schema `history` (created by dbt on first snapshot run). Bronze/Silver/Gold remain distinct.

Manual validation within the scheduler container:

```powershell
cd data_warehouse
docker compose up -d --build
docker compose exec airflow-scheduler dbt debug --project-dir /opt/airflow/dbt
docker compose exec airflow-scheduler dbt parse --project-dir /opt/airflow/dbt
# Only after Silver commit:
docker compose exec airflow-scheduler dbt run --project-dir /opt/airflow/dbt --select path:models/silver
docker compose exec airflow-scheduler dbt snapshot --project-dir /opt/airflow/dbt --select snap_stops
docker compose exec airflow-scheduler dbt build --project-dir /opt/airflow/dbt --select path:models/gold
```

Note: DAG changes are integration work, not part of task 2.3; coordinate with Airflow task.
