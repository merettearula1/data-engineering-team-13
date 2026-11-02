"""
Tartu Transit pipeline: ingest bus + weather data into bronze, check data quality,
then build and test the silver/gold layers with dbt.

The ingestion tasks are placeholders until the ingestion code is ready.
Contract for each ingestion task: load ONLY the given run_date into its bronze table,
deleting that date's rows first, so reruns never create duplicates (idempotent).
"""
import pendulum
from airflow.providers.standard.operators.bash import BashOperator
from airflow.sdk import Param, dag, task

DBT_BIN = "/home/airflow/dbt_venv/bin/dbt"
DBT_PROJECT_DIR = "/opt/airflow/dbt"
LOCAL_TZ = "Europe/Tallinn"


@dag(
    dag_id="tartu_transit_pipeline",
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
)
def tartu_transit_pipeline():

    @task
    def resolve_run_date(**context) -> str:
        """Use the run_date parameter if given, otherwise the logical date (or today for
manual runs)."""
        if context["params"].get("run_date"):
            return context["params"]["run_date"]
        logical_date = context.get("logical_date") or pendulum.now(LOCAL_TZ)
        return logical_date.strftime("%Y-%m-%d")

    @task
    def ingest_weather(run_date: str) -> None:
        # TODO (weather owner): fetch ilmateenistus.ee observations -> bronze.weather_raw for run_date
        print(f"[placeholder] ingest weather for {run_date}")

    @task
    def ingest_bus(run_date: str) -> None:
        # TODO (bus owner): load bus live + schedule data -> bronze tables for run_date
        print(f"[placeholder] ingest bus data for {run_date}")

    @task
    def dq_check_bronze(run_date: str) -> None:
        # TODO: once bronze tables exist, query them and raise ValueError on e.g.
        #   - 0 rows loaded for run_date
        #   - NULL trip_id / stop_id
        #   - duplicate (trip_id, stop_index, service_date)
        print(f"[placeholder] data-quality checks for {run_date}")

    dbt_run = BashOperator(
        task_id="dbt_run",
        bash_command=f"{DBT_BIN} run --project-dir {DBT_PROJECT_DIR}",
    )

    dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command=f"{DBT_BIN} test --project-dir {DBT_PROJECT_DIR}",
    )

    run_date = resolve_run_date()
    [ingest_weather(run_date), ingest_bus(run_date)] >> dq_check_bronze(run_date) >> dbt_run >> dbt_test


tartu_transit_pipeline()
