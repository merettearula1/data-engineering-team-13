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
        "run_date": Param(
            None,
            type=["null", "string"],
            description="Date to process (YYYY-MM-DD). Empty = the run's logical date.",
        ),
    },
    tags=["tartu", "bronze", "dbt"],
) as dag:

    @task
    def resolve_run_date(**context) -> str:
        if context["params"].get("run_date"):
            return context["params"]["run_date"]
        return context["logical_date"].strftime("%Y-%m-%d")

    @task
    def ingest_weather(run_date: str) -> dict:
        return ingest(run_date=run_date, datasets={"weather"})

    @task
    def ingest_bus(run_date: str) -> dict:
        return ingest(run_date=run_date, datasets=BUS_DATASETS)

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

    run_date = resolve_run_date()
    weather = ingest_weather(run_date)
    bus = ingest_bus(run_date)
    check = dq_check_bronze(weather, bus)
    [weather, bus] >> check >> dbt_run >> dbt_test
