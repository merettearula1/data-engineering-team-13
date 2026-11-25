# Tartu Transit Analytics — Gold layer (dbt, Project 2 task 2.3)

The Gold layer turns cleaned **Silver** data into a star schema for analysing bus punctuality, driving speed and weather in Tartu. It is part of the `tartu_transit` dbt project, located in [`data_warehouse/dbt/`](dbt/).

**Current implementation:** The Silver and Gold models, stop-history snapshot, tests and three Airflow DAGs are in the repository. This README documents the implementation and how to verify it.

## 1. Data flow

```text
Ridango bus data + Estonian Weather Service
                 |
     tartu_bronze (Airflow)
                 |
       bronze.raw_events (JSONB)
                 |
     tartu_silver (Airflow)
       dbt seed -> dbt run Silver -> dbt test Silver
                  -> dbt snapshot snap_stops
                 |
     silver views/tables + history.snap_stops
                 |
      tartu_gold (Airflow)
       dbt run Gold -> dbt test Gold
                 |
      gold dimensions and facts
```

The three DAGs use **Airflow Assets**: a successful upstream DAG triggers the next one. The Silver DAG runs the `snap_stops` snapshot before Gold builds `dim_stop`. See [`dags/tartu_bronze.py`](dags/tartu_bronze.py), [`dags/tartu_silver.py`](dags/tartu_silver.py) and [`dags/tartu_gold.py`](dags/tartu_gold.py). The overall setup is documented in [`README.md`](README.md).

## 2. Gold star schema

**Fact tables (grain = what one row represents)**

| Table | Grain | Main information |
|---|---|---|
| `gold.fact_bus_performance` | One **service date × trip ID × stop index** | Scheduled and predicted arrival times, predicted delay, on-time flag, driving speed and links to route/stop/weather |
| `gold.fact_weather` | One **station × observation timestamp** | Temperature, precipitation, wind, visibility and weather phenomenon/category |

The stop **index** is part of the bus fact grain because a circular route can visit the same stop more than once on one trip. Repeated source observations are ranked, with real-time estimates preferred and then the latest observation chosen.

**Dimensions**

| Table | Description |
|---|---|
| `gold.dim_date` | Calendar date, weekday, weekend and fixed-holiday flag |
| `gold.dim_time` | Minute of day and peak-hour/day-part labels (1,440 rows) |
| `gold.dim_route` | Bus route and direction metadata (Type 1: latest details) |
| `gold.dim_trip` | Trip and destination metadata (Type 1: latest details) |
| `gold.dim_stop` | Bus stop names, coordinates and historical versions (Type 2) |

`dim_stop` is created from [`dbt/snapshots/snap_stops.sql`](dbt/snapshots/snap_stops.sql). The snapshot stores versions in the `history` schema when stop attributes change. `dim_stop` also estimates a district using the nearest centre from the dbt seed `tartu_district_centres`; stops more than 2.5 km from every centre are labelled `Outside Tartu`. District labels are approximate, especially near boundaries.

The model SQL lives in [`dbt/models/gold/`](dbt/models/gold/) and its field descriptions and standard tests in [`dbt/models/gold/schema.yml`](dbt/models/gold/schema.yml).

### Calculations and joins

- **Predicted punctuality:** `on_time_flag = true` when the API's real-time arrival-delay estimate is between **−180 and +180 seconds**. Timetable-only rows have NULL delay/on-time measures, not a misleading zero-minute delay. These are **predictions**, not independently observed actual arrivals.
- **Weather match:** the bus fact links to the nearest `Tartu-Tõravere` weather observation within **60 minutes** of its event time; if none exists, `weather_key` is NULL.
- **Driving speed:** `silver_section_speeds` derives speed from GPS distance and elapsed driving time **between consecutive stops**, excluding standing time at the stops. A speed is available only when GPS coverage is sufficient; it is not simply the API-reported instantaneous speed. The result appears in `fact_bus_performance.avg_speed_kmh`.
- **Time zone:** date/time keys use `Europe/Tallinn`. Keys for routes, trips, weather and bus facts are deterministic MD5 text keys (not PostgreSQL `SERIAL` IDs).
- **Dependencies:** `{{ ref('silver_stop_events') }}`, `{{ ref('silver_weather') }}`, other Silver `ref()` calls, snapshot references and references between Gold models let dbt determine the build order.

## 3. Input models

The Gold models read these existing upstream dbt models:

| Upstream model | Used for |
|---|---|
| `silver_routes` | `dim_route` |
| `silver_stop_events` (built using `silver_trips`) | `dim_trip`, bus performance and trip/route/stop matching |
| `silver_stops` | `snap_stops` stop-history snapshot |
| `silver_weather` | `fact_weather` |
| `silver_section_speeds` (built using `silver_live_positions`) | GPS-based road-section speed in bus performance |
| `tartu_district_centres` (dbt seed) | Approximate districts in `dim_stop` |

## 4. Running the pipeline

### Through Airflow (normal workflow)

From `data_warehouse/` in a terminal, start the containers:

```powershell
docker compose up -d --build
docker compose ps
```

Open **Airflow at <http://localhost:8080>**. Ensure `tartu_silver` and `tartu_gold` are unpaused, then enable/trigger `tartu_bronze`. On success, Airflow automatically runs Silver and then Gold.

### Manual dbt verification (Windows PowerShell)

Run these commands **from `data_warehouse/`**, with Docker running. dbt is installed inside the Airflow container, not necessarily on Windows:

```powershell
# Connection and dbt model configuration
docker compose exec airflow-scheduler /opt/airflow/dbt_venv/bin/dbt debug --project-dir /opt/airflow/dbt
docker compose exec airflow-scheduler /opt/airflow/dbt_venv/bin/dbt parse --project-dir /opt/airflow/dbt

# Same essential build order as the layered Airflow DAGs
docker compose exec airflow-scheduler /opt/airflow/dbt_venv/bin/dbt seed --project-dir /opt/airflow/dbt
docker compose exec airflow-scheduler /opt/airflow/dbt_venv/bin/dbt run --project-dir /opt/airflow/dbt --select path:models/silver
docker compose exec airflow-scheduler /opt/airflow/dbt_venv/bin/dbt test --project-dir /opt/airflow/dbt --select path:models/silver --indirect-selection cautious
docker compose exec airflow-scheduler /opt/airflow/dbt_venv/bin/dbt snapshot --project-dir /opt/airflow/dbt --select snap_stops
docker compose exec airflow-scheduler /opt/airflow/dbt_venv/bin/dbt run --project-dir /opt/airflow/dbt --select path:models/gold
docker compose exec airflow-scheduler /opt/airflow/dbt_venv/bin/dbt test --project-dir /opt/airflow/dbt --select path:models/gold
```

**Do not run the manual build at the same time as the Airflow DAGs** against the same database. dbt's project and profile live in `dbt/dbt_project.yml` and `dbt/profiles.yml`; Docker Compose supplies the `WAREHOUSE_*` connection environment variables. Do not commit `.env` or passwords.

## 5. Validation and documentation

- `schema.yml` defines model and column descriptions plus tests such as `not_null`, `unique` and `relationships`.
- Custom SQL data-quality checks are in [`dbt/tests/`](dbt/tests/) (including fact grain, linked keys, schedule-only delay handling, on-time threshold, stop-version overlap and weather-date validity).
- After a successful build, run selected checks in PostgreSQL using [`docs/VERIFY_IN_PGADMIN.sql`](docs/VERIFY_IN_PGADMIN.sql). Open **pgAdmin at <http://localhost:5050>**, connect to the `warehouse` database and use the Query Tool.
- The overall [`README.md`](README.md) contains Airflow DAG screenshots and a dbt lineage diagram. dbt documentation can also be generated with `dbt docs generate` when the project can connect to its database.

**Suggested checks:** inspect fact/dimension row counts; verify no duplicate `(date_key, trip_key, stop_index)` values; check missing foreign keys and weather matches; and calculate predicted on-time percentage **only** for rows with a non-NULL `on_time_flag`.

## 6. Changes from Project 1 and limitations

- The star schema retains **two facts and five dimensions**, but uses reproducible MD5 text keys rather than `SERIAL` keys for several tables.
- Bus delay is an **API real-time prediction**; we cannot claim verified actual arrival punctuality from it.
- Speed is inferred from eligible GPS track segments between stops; missing or incomplete GPS coverage means speed can be NULL.
- Weather is matched by nearest station observation within ±60 minutes, not by direct measurement at each bus stop.
- The date dimension's holiday flag includes fixed holidays only; moving holidays are not covered.
- The stop-history snapshot records **when dbt detects changed details**, which may differ from the physical time of a stop change.
- Gold SQL models are currently **full-refresh tables**, rather than incremental models optimized for very large datasets.

For how to start the full infrastructure and Airflow pipeline, see the main [`data_warehouse/README.md`](README.md).
