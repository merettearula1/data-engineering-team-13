"""Gold layer: build and test the star schema (dims + facts) from silver with dbt.

Triggered automatically whenever `tartu_silver` finishes successfully.
"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))  # for tartu_common

import pendulum
from airflow.providers.standard.operators.bash import BashOperator
from airflow.sdk import DAG

from tartu_common import GOLD_ASSET, LOCAL_TZ, SILVER_ASSET, dbt

with DAG(
    dag_id="tartu_gold",
    description="Silver -> gold: build and test the star schema",
    schedule=[SILVER_ASSET],
    start_date=pendulum.datetime(2026, 11, 1, tz=LOCAL_TZ),
    catchup=False,
    is_paused_upon_creation=False,  # only runs when the upstream layer emits its Asset
    tags=["tartu", "gold", "dbt"],
) as dag:

    dbt_run_gold = BashOperator(
        task_id="dbt_run_gold",
        bash_command=dbt("run", "--select path:models/gold"),
    )
    # Includes schema tests on gold models and the singular tests in dbt/tests/
    dbt_test_gold = BashOperator(
        task_id="dbt_test_gold",
        bash_command=dbt("test", "--select path:models/gold"),
        outlets=[GOLD_ASSET],
    )

    dbt_run_gold >> dbt_test_gold
