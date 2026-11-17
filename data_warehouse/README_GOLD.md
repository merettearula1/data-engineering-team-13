# Tartu Transit Analytics — task 2.3 Transformation (dbt)

- Active dbt project: **`data_warehouse/dbt/`**, dbt package name `tartu_transit`, profile `tartu_transit`.
- Existing `generate_schema_name.sql` maps `schema='gold'` to physical PostgreSQL schema `gold`, without `public_` prefix.
- Existing Airflow DAG calls dbt with `--project-dir /opt/airflow/dbt`, uses Docker venv PATH and `WAREHOUSE_*` credentials, and loads to `bronze.raw_events`.
- There is **no completed `models/silver/` directory in this ZIP**. Missing Silver `ref()` calls will block `dbt parse`/`dbt build` until their models are merged.

## Files and design

```text
data_warehouse/dbt/
  models/gold/
    dim_date.sql
    dim_time.sql
    dim_route.sql
    dim_trip.sql
    dim_stop.sql
    fact_weather.sql
    fact_bus_performance.sql
    schema.yml
  snapshots/snap_stops.sql
  tests/*.sql
  docs/SILVER_HANDOFF.md
  docs/AIRFLOW_HANDOFF.md
  docs/VERIFY_IN_PGADMIN.sql
optional_airflow/tartu_transit_pipeline.py     # DO NOT copy if not necessary
```

The existing `dbt_project.yml`, `profiles.yml` and schema macro are compatible as-is: do not overwrite them. The individual model `config()` clauses set materialization=`table`, schema=`gold`.

**Facts and grain:**
- `fact_bus_performance`: exactly 1 `(service_date, trip_id, stop_index)`; trip-stop event is deduplicated to latest eligible observation. Source delay may be a real-time *prediction*, not an observed arrival.
- `fact_weather`: exactly 1 `(station_name, observed_at)` source observation timestamp.

**Dimensions:** `dim_date`, `dim_time`, `dim_route` (Type 1), `dim_trip` (Type 1), `dim_stop` (Type 2 via dbt snapshot).

**Documented differences from Project 1**: stable MD5 text surrogate keys in place of SERIAL integer keys for route/trip/stop/weather/bus fact; weather matched to nearest ±60min Tartu-Tõravere reading; fixed-only holiday flags; full-refresh models (not yet optimized for large live history).

## Windows VS Code terminal

1. `git pull`, then `git switch -c feature/gold-dbt-schema` in the existing repo. Keep main branch unchanged.
2. copy/merge `data_warehouse/dbt/` into the same folder in the cloned Git repository. No `.env` or passwords are included.
3. Open `data_warehouse/dbt/docs/SILVER_HANDOFF.md` and confirm Silver names and columns. Contracted dbt models: `silver_routes`, `silver_stops`, `silver_stop_events`, `silver_weather`, `silver_live_positions`.
4. When Silver models are merged, start Docker (from `data_warehouse/`): `docker compose up -d --build`.
5. From inside `data_warehouse/` run:

   ```powershell
   docker compose exec airflow-scheduler dbt debug --project-dir /opt/airflow/dbt
   docker compose exec airflow-scheduler dbt parse --project-dir /opt/airflow/dbt
   docker compose exec airflow-scheduler dbt run --project-dir /opt/airflow/dbt --select path:models/silver
   docker compose exec airflow-scheduler dbt snapshot --project-dir /opt/airflow/dbt --select snap_stops
   docker compose exec airflow-scheduler dbt build --project-dir /opt/airflow/dbt --select path:models/gold
   ```

   There is **no reason to run these last three now** if the Silver models is not included yet. The first two also need correct dbt references, so `dbt parse` is expected to report missing models until Silver is merged. No Gold tables have been created yet.

6. Validate row counts and keys with `data_warehouse/dbt/docs/VERIFY_IN_PGADMIN.sql`, and inspect dbt results. `dbt build` runs model tests as part of the build
7. From Airflow - update the DAG sequence per `docs/AIRFLOW_HANDOFF.md` (the optional edited DAG is included). This is needed for task 2.4, not needed to write the 2.3 models
8. When validation works, in repo root:

   ```powershell
   git status
   git add data_warehouse/dbt
   git commit -m "Implement Gold star schema, snapshot, tests and docs"
   git push -u origin feature/gold-dbt-schema
   ```

   Open a PR (Pull Request) and share the Silver model contract and Airflow integration doc

## dbt commands explained simply

- `dbt run`: executes model SQL and creates PostgreSQL tables or views.
- `dbt snapshot`: records changed stop attributes with valid-from / valid-to history.
- `dbt build`: builds selected models and executes their declared tests.
- `ref('silver_weather')`: tells dbt to read that named Silver model and records a dependency in the DAG. If it does not exist, dbt stops, rather than silently using unrelated data.

## Limitations and open dependencies

This patch was checked statically for YAML syntax, SQL file presence and `ref()` graph, but **cannot be run end-to-end without actual Silver outputs and a running project's PostgreSQL instance**. Currently no production data or Silver models. The Gold model assumptions are documented in `docs/SILVER_HANDOFF.md`.

Stop-history timestamps reflect **when dbt noticed a change**, not necessarily when the bus stop physically changed. Validate the source data's history before claiming precise historical stop positions. Distinguish real-time predictions from actual arrival records in the final project report.
