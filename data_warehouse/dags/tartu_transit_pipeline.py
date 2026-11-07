"""Load bus and weather data, validate, then run dbt transformations."""
import sys
sys.path.insert(0, "/opt/airflow")

import pendulum
from airflow import DAG
from airflow.decorators import task
from airflow.models.param import Param
from airflow.operators.bash import BashOperator

from ingestion.pipeline import ingest

DBT_PROJECT_DIR = "/opt/airflow/dbt"
LOCAL_TZ = "Europe/Tallinn"
BUS_DATASETS = {
    "bus_departures",
    "bus_live",
    "bus_routes",
    "bus_stops",
    "bus_trip_stop_times",
    "bus_trips",
}


with DAG(
    dag_id="tartu_transit_pipeline",
    description="Ingest public bus and weather files into the warehouse",
    schedule="@daily",
    start_date=pendulum.datetime(2026, 11, 1, tz=LOCAL_TZ),
    catchup=False,
    params={
        "start_date": Param(
            None,
            type=["null", "string"],
            description="Load data from this date onwards (YYYY-MM-DD). Empty = today and yesterday.",
        ),
    },
    tags=["tartu", "bronze", "dbt"],
) as dag:

    @task
    def resolve_date_range(**context) -> tuple[str, str | None]:
        start_date = context["params"].get("start_date")
        if start_date:
            return start_date, None
        logical_date = context["logical_date"]
        return (
            logical_date.subtract(days=1).to_date_string(),
            logical_date.to_date_string(),
        )

    @task
    def ingest_weather(date_range: tuple[str, str | None]) -> dict:
        return ingest(start_date=date_range[0], end_date=date_range[1], datasets={"weather"})

    @task
    def ingest_bus(date_range: tuple[str, str | None]) -> dict:
        return ingest(start_date=date_range[0], end_date=date_range[1], datasets=BUS_DATASETS)

    @task
    def dq_check_bronze(weather: dict, bus: dict) -> None:
        """Make the ingestion quality result visible as its own DAG task."""
        processed_files = sum(
            result["loaded_files"] + result["skipped_files"]
            for result in (weather, bus)
        )
        if processed_files == 0:
            raise ValueError("Data-quality check failed: no bus or weather files found")
        print(f"Data-quality check passed: {weather=}, {bus=}")

    dbt_run = BashOperator(
        task_id="dbt_run",
        bash_command=f"dbt run --project-dir {DBT_PROJECT_DIR}",
    )

    dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command=f"dbt test --project-dir {DBT_PROJECT_DIR}",
    )

    date_range = resolve_date_range()
    weather = ingest_weather(date_range)
    bus = ingest_bus(date_range)
    check = dq_check_bronze(weather, bus)
    [weather, bus] >> check >> dbt_run >> dbt_test
