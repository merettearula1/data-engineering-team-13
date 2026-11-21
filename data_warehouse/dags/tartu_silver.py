"""Silver layer: transform bronze raw events into cleaned silver views with dbt.

Triggered automatically whenever `tartu_bronze` finishes successfully.
Also takes the `snap_stops` snapshot (SCD2 history of silver_stops), which gold's dim_stop needs.
"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))  # for tartu_common

import pendulum
from airflow.providers.standard.operators.bash import BashOperator
from airflow.sdk import DAG

from tartu_common import BRONZE_ASSET, LOCAL_TZ, SILVER_ASSET, dbt

with DAG(
    dag_id="tartu_silver",
    description="Bronze -> silver: build and test silver dbt models, snapshot stops",
    schedule=[BRONZE_ASSET],
    start_date=pendulum.datetime(2026, 11, 1, tz=LOCAL_TZ),
    catchup=False,
    is_paused_upon_creation=False,  # only runs when the upstream layer emits its Asset
    tags=["tartu", "silver", "dbt"],
) as dag:

    dbt_run_silver = BashOperator(
        task_id="dbt_run_silver",
        bash_command=dbt("run", "--select path:models/silver"),
    )
    # cautious: skip tests that also depend on gold models, which aren't rebuilt yet
    dbt_test_silver = BashOperator(
        task_id="dbt_test_silver",
        bash_command=dbt("test", "--select path:models/silver --indirect-selection cautious"),
    )
    dbt_snapshot_stops = BashOperator(
        task_id="dbt_snapshot_stops",
        bash_command=dbt("snapshot", "--select snap_stops"),
        outlets=[SILVER_ASSET],
    )

    dbt_run_silver >> dbt_test_silver >> dbt_snapshot_stops
