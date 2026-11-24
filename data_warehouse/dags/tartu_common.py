"""Shared settings for the layered Tartu transit DAGs (bronze -> silver -> gold).

The three layer DAGs are chained with Airflow Assets: each DAG marks its layer's
Asset as updated when it succeeds, and the next DAG is scheduled on that Asset.
"""
from airflow.sdk import Asset

DBT_PROJECT_DIR = "/opt/airflow/dbt"
LOCAL_TZ = "Europe/Tallinn"

BRONZE_ASSET = Asset("tartu_bronze")
SILVER_ASSET = Asset("tartu_silver")
GOLD_ASSET = Asset("tartu_gold")


def dbt(cmd: str, args: str = "") -> str:
    """Build a dbt CLI command against the mounted project."""
    return f"dbt {cmd} --project-dir {DBT_PROJECT_DIR} {args}".strip()
