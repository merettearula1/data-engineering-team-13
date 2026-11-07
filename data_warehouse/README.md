# Airflow data warehouse

The [`tartu_transit_pipeline`](dags/tartu_transit_pipeline.py) DAG loads collector datasets from the public Azure
Blob manifest into PostgreSQL, then runs the dbt models.

### Ingestion code description:

- [`pipeline.py`](ingestion/pipeline.py) runs ingestion workflow and  loading.
- [`storage.py`](ingestion/storage.py) downloads the public manifest and raw data files.
- [`readers.py`](ingestion/readers.py) unzips/reads JSON and JSONL snapshots.
- [`validation.py`](ingestion/validation.py) verifies file size/checksum and performs data-quality checks.
- [`loader.py`](ingestion/loader.py) creates and loads the Bronze tables. (into `bronze.raw_events`)


In the pipeline we can optionally filter files by a DAG-run `run_date`, such as `2026-11-06`.


## Setup

Run to create a local `.env` file. (Chose this over .env.example as we can generate logins).

### Bash (Linux)

```bash
cd data_warehouse

umask 077

cat > .env <<EOF
POSTGRES_PASSWORD=$(openssl rand -hex 24)
AIRFLOW_FERNET_KEY=$(python3 -c 'import base64, os; print(base64.urlsafe_b64encode(os.urandom(32)).decode())')
AIRFLOW_JWT_SECRET=$(openssl rand -hex 64)
AIRFLOW_API_SECRET_KEY=$(openssl rand -hex 32)
AIRFLOW_ADMIN_USERNAME=admin
AIRFLOW_ADMIN_PASSWORD=$(openssl rand -hex 16)
AIRFLOW_ADMIN_EMAIL=admin@example.com
PGADMIN_DEFAULT_EMAIL=admin@example.com
PGADMIN_DEFAULT_PASSWORD=$(openssl rand -hex 16)
EOF

chmod 600 .env

```

### PowerShell (Windows)

```powershell
cd data_warehouse

$rand = [Security.Cryptography.RandomNumberGenerator]::Create()

function Secret($n) {
    $b = New-Object byte[] $n
    $rand.GetBytes($b)
    ([BitConverter]::ToString($b) -replace '-', '').ToLower()
}

$b = New-Object byte[] 32
$rand.GetBytes($b)
$fernet = [Convert]::ToBase64String($b).Replace('+','-').Replace('/','_')

@"
POSTGRES_PASSWORD=$(Secret 24)
AIRFLOW_FERNET_KEY=$fernet
AIRFLOW_JWT_SECRET=$(Secret 64)
AIRFLOW_API_SECRET_KEY=$(Secret 32)
AIRFLOW_ADMIN_USERNAME=admin
AIRFLOW_ADMIN_PASSWORD=$(Secret 16)
AIRFLOW_ADMIN_EMAIL=admin@example.com
PGADMIN_DEFAULT_EMAIL=admin@example.com
PGADMIN_DEFAULT_PASSWORD=$(Secret 16)
"@ | Set-Content .env -Encoding utf8

$rand.Dispose()

```


### Then run (your docker) and the Docker:
```
docker compose build
docker compose up -d
```

### UI links (Airflow and pgAdmin)

Airflow: http://localhost:8080

pgAdmin: http://localhost:5050

To Connect the PostGRE server to pgadmin use

|Var|Value|
|---|---|
|Name|data_warehouse|
|Host|5432|
|Maintenance db|warehouse|
|Username|warehouse_admin|
|Password|POSTGRES_PASSWORD (in .env)|

---

To trigger a date-specific run in Airflow, use the DAG configuration:

```json
{"run_date": "2026-10-21"}
```
