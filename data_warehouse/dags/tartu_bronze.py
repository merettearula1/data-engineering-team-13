"""Bronze layer: ingest raw bus and weather files into the warehouse `bronze` schema."""
import sys
from pathlib import Path
sys.path.insert(0, "/opt/airflow")
sys.path.insert(0, str(Path(__file__).parent))  # for tartu_common

import pendulum
from airflow.sdk import DAG, Param, task

from ingestion.pipeline import ingest
from tartu_common import BRONZE_ASSET, LOCAL_TZ

BUS_DATASETS = {
    # "bus_departures",
    "bus_live",
    "bus_routes",
    "bus_stops",
    "bus_trip_stop_times",
    "bus_trips",
}


with DAG(
    dag_id="tartu_bronze",
    description="Ingest public bus and weather files into the bronze schema",
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
    tags=["tartu", "bronze"],
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

    @task(retries=3, retry_delay=pendulum.duration(minutes=1))
    def ingest_weather(date_range: tuple[str, str | None]) -> dict:
        return ingest(start_date=date_range[0], end_date=date_range[1], datasets={"weather"})

    @task(retries=3, retry_delay=pendulum.duration(minutes=1))
    def ingest_bus(date_range: tuple[str, str | None]) -> dict:
        return ingest(start_date=date_range[0], end_date=date_range[1], datasets=BUS_DATASETS)

    @task(outlets=[BRONZE_ASSET])
    def dq_check_bronze(weather: dict, bus: dict) -> None:
        """Fail if nothing was found; on success, signal the silver DAG via the bronze Asset."""
        processed_files = sum(
            result["loaded_files"] + result["skipped_files"]
            for result in (weather, bus)
        )
        if processed_files == 0:
            raise ValueError("Data-quality check failed: no bus or weather files found")
        print(f"Data-quality check passed: {weather=}, {bus=}")

    date_range = resolve_date_range()
    dq_check_bronze(ingest_weather(date_range), ingest_bus(date_range))
