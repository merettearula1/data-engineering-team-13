# Tartu Transit Analytics using live bus data and live weather data

## Project part 1

#### Used data, architecture and modeling info can be found in the [datasets_architecture folder](datasets_architecture) and [readme](datasets_architecture/README.md).

## Raw data collection

#### We collected raw data using a Microsoft Azure VM that is running continuously (as the pilet.ee api doesn't offer legacy data). 
#### For data storage we used Azure storage blobs that are anonymously accessible. Full code can be found in the [raw_data_collection folder](raw_data_collection) and [readme](raw_data_collection/README.md).

## Project part 2 

#### Data warehouse implementation and ETL pipelines can be found in the [data_warehouse folder](data_warehouse) and [readme](data_warehouse/README.md).


## Setup & run
Requirements: Docker Desktop.

```bash
cp .env.example .env          # then set POSTGRES_PASSWORD
docker compose up -d --build
```
- Airflow UI: http://localhost:8080 → unpause and trigger `tartu_transit_pipeline`
- Warehouse: Postgres on `localhost:5433`, database `tartu_transit`, schemas `bronze` /
`silver` / `gold`
- Reset the database from scratch: `docker compose down -v && docker compose up -d`



---
This project is developed as part of the Data Engineering 2026/27 fall course at the University of Tartu.
