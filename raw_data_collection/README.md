# Raw data collection

This folder collects and stores raw Tartu bus and weather data. The collectors
do not transform the data or use a database. They save source responses locally
so they can be used later by the warehouse and dbt projects or in our case uploaded to cloud storage.

## Folder structure

| Folder | Contents |
|---|---|
| [`collectors/`](collectors/) | Bus and weather collectors. These are the services that should be started for local collection. |
| [`common/`](common/) | Shared configuration, HTTP, storage, and discovery helpers used by the collectors. |
| [`blob_uploader/`](blob_uploader/) | Optional Azure Blob Storage uploader. Do not start this for local-only collection. |
| [`tests/`](tests/) | Scripts for checking and reporting on collected data. |
| [`data/`](data/) | Local output directory. Raw data is written below `data/raw/`. |
| [`uploader_state/`](uploader_state/) | Local state used only by the optional blob uploader. |

## Collections

- `bus-live`: continuous live vehicle positions
- `weather`: weather observations from Tartu-Tõravere
- `bus-reference`: bus stops and routes
- `bus-trips`: trips for discovered routes
- `bus-departures`: real-time departures for bus stops
- `bus-trip-stop-times`: scheduled stop times for discovered trips

The collectors save data in UTC partitions under
`data/raw/<source>/date=YYYY-MM-DD/`.

## Setup

```bash
cd raw_data_collection
cp .env.example .env
```

## Start Docker

Start the collectors only. 

```bash
docker compose up -d --build \
  bus-live \
  weather \
  bus-reference \
  bus-trips \
  bus-departures \
  bus-trip-stop-times
```
This command deliberately skips the uploader as uploading needs a set Azure identity (only for the collection VM).

Optionally to start the `blob-uploader`:
```bash
mkdir -p uploader_state
docker compose up -d --build --no-deps blob-uploader
```


Stop the collectors without deleting the local data:

```bash
docker compose down
```


## Measure the collected data size/rows

```bash
python tests/report_collection.py
```

## Disclaimer

Some code in this folder was developed or restructured with the assistance of AI tools. 
The core ideas, architecture, and concepts are our own.
