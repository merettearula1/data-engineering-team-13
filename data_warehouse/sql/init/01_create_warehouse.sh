#!/bin/bash
# Runs once, when the Postgres volume is first created.
# Creates the analytical warehouse DB and the medallion-layer schemas.
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<EOSQL
CREATE DATABASE $WAREHOUSE_DB;
EOSQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$WAREHOUSE_DB" <<EOSQL
CREATE SCHEMA IF NOT EXISTS bronze;   -- raw data, loaded by Airflow tasks
CREATE SCHEMA IF NOT EXISTS silver;   -- cleaned data, managed by dbt
CREATE SCHEMA IF NOT EXISTS gold;     -- star schema, managed by dbt
EOSQL

