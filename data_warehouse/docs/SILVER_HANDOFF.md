# Silver → Gold

No `data_warehouse/dbt/models/silver/` implementation yet, so names are a **contract proposal**

## Confirmed inputs

- PostgreSQL table `bronze.raw_events` contains `source_name`, `payload` (JSONB), `blob_path`, `checksum`, `record_number`, `loaded_at`
- `source_name` values produced by the current ingestion code: `bus_departures`, `bus_live`, `bus_routes`, `bus_stops`, `bus_trip_stop_times`, `bus_trips`, `weather`
- `bus_routes` / `bus_stops`: outer wrapper `{"endpoint":..., "fetched_at":..., "payload": ...}`. Route/stop arrays may be nested beneath `data`, `items`, `results`, `routes` or `stops`; inspect real rows before flattening
- `bus_trip_stop_times`: outer wrapper includes `trip_id`, `fetched_at`, `payload`; each stop item has fields such as `stopIndex`, `scheduledArrival`, `arrivalDelay`, `realtime`
- `bus_trips`: outer wrapper includes `route_id`, `fetched_at`, `payload` and supplies the route-to-trip relationship
- `bus_live`: wrapper has `fetched_at` and `payload` as a **list of vehicle-status objects**; each vehicle has `tripId`, `updateTime`, `startDate`, `speed`, etc
- `weather`: a flat record with `name`, `source_observation_time`, `fetched_at`, `precipitations`, `visibility`, `airtemperature`, `windspeed`, `windspeedmax`, `phenomenon`

## Required normalized dbt Silver models

| dbt model | Required fields | Conditions |
|---|---|---|
| `silver_routes` | `route_id text`, `short_name text`, `long_name text`, `mode text` | Exactly one **current** row per `route_id` (route SCD Type 1). |
| `silver_stops` | `stop_id text`, `stop_code text`, `stop_name text`, `latitude numeric`, `longitude numeric`, `district text` | Exactly one **current** row per `stop_id`; nullable district is acceptable. Gold `snap_stops` records historical changes. |
| `silver_stop_events` | `service_date date`, `trip_id text`, `route_id text`, `stop_id text`, `stop_index integer`, `scheduled_arrival timestamptz`, `scheduled_departure timestamptz`, `realtime_arrival timestamptz`, `realtime_departure timestamptz`, `arrival_delay_sec integer`, `departure_delay_sec integer`, `is_realtime boolean`, `is_canceled boolean`, `observation_time timestamptz`, `service_id text`, `trip_headsign text` | One row per *observation* is okay; Gold chooses latest eligible update per `(service_date,trip_id,stop_index)`. **`route_id` must be joined/enriched** from `bus_trips` or departures: it is not directly provided by trip stop-times. `service_date` must be the service day, not naively the local arrival calendar day for overnight trips. |
| `silver_weather` | `station_name text`, `observed_at timestamptz`, `precipitation_mm numeric`, `visibility_km numeric`, `temperature_c numeric`, `wind_speed_ms numeric`, `wind_speed_max_ms numeric`, `weather_category text` | Deduplicate `(station_name, observed_at)`; use the source observation time when available. Fetch time is not necessarily observation time. Normalize phenomenon to clear/rain/snow/fog/other. |
| `silver_live_positions` | `trip_id text`, `service_date date`, `update_time timestamptz`, `speed_kmh numeric` | Unnest vehicle-status list; convert `speed` m/s × 3.6 to km/h per the team's `Datasets.md`. API trip IDs must match the stop events or be normalized. `startDate` of e.g. `20261001` is parsed as date. |

### Mandatory data-quality rules upstream

- Verify `scheduled_arrival` and `stop_index` are populated for stop events; otherwise the Gold key/time dimension fails
- Do not treat timetable-only (`realtime=false`) `arrivalDelay=0` as a measured zero delay. Gold nulls out its measures.
- Choose `service_date` consistently for all stop events and GPS records, particularly for overnight trips and time-zone shifts
- Deduplicate current route/stop metadata. Multiple versions of a stop belong in dbt snapshot (`history.snap_stops`), not in the input `silver_stops` table
- Validate `weather.observed_at` parses correctly. If the source timestamp is epoch seconds, convert it as seconds (not milliseconds). If missing, document when `fetched_at` is used instead

### Silver layer adaptation

1. What are the **actual model names** and final column types? If different, update only the Gold `ref('...')` calls / column adapters.
2. Can `silver_stop_events` enrich `route_id` for every trip? If not, Gold `route_key` will be null and tests fail.
3. Are GPS `tripId` values the same identifiers as those in the REST stop-times API? If not, speed cannot be matched without a mapping.
4. Will the final Silver model keep historic event observations instead of only the last daily snapshot?

Gold does **not** invent missing arrival predictions or missing weather observations.
