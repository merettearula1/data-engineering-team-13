## Data Dictionary

# Fact Tables

## 1. `FACT_BUS_PERFORMANCE`

Description: Preprocessed data that is taken from STAGING_BUS_LIVE and STAGING_BUS_SCHEDULE

Grain: 1 row represents 1 trip at 1 stop position


| Variable | Type | Description |
|---|---|---|
| `performance_key` | BIGINT (PK) | Unique record key |
| `weather_key` | INTEGER (FK) | Reference to the weather fact table |
| `date_key` | INTEGER (FK) | Reference to the date dimension |
| `time_key` | INTEGER (FK) | Reference to the time dimension |
| `route_key` | INTEGER (FK) | Reference to the route dimension |
| `trip_key` | INTEGER (FK) | Reference to the trip dimension |
| `stop_key` | INTEGER (FK) | Reference to the stop dimension |
| `scheduled_arrival` | TIMESTAMPTZ | Scheduled arrival time at the stop |
| `scheduled_departure` | TIMESTAMPTZ | Scheduled departure time from the stop |
| `realtime_arrival` | TIMESTAMPTZ | Realtime arrival time, when available |
| `realtime_departure` | TIMESTAMPTZ | Realtime departure time, when available |
| `arrival_delay_sec` | INTEGER | Arrival delay in seconds |
| `departure_delay_sec` | INTEGER | Departure delay in seconds |
| `on_time_flag` | BOOLEAN | Indicates whether the bus arrived and departed on +-3 min time |
| `is_realtime` | BOOLEAN | Indicates whether realtime timing information is available |
| `observation_time` | TIMESTAMPTZ | Time of the reported observation |
| `avg_speed_kmh` | NUMERIC | Average bus speed in kilometres per hour |
| `gps_ping_count` | INTEGER | Number of GPS observations used |
| `is_canceled` | BOOLEAN | Indicates whether the trip is cancelled |
| `stop_index` | INTEGER | Position of the stop within the trip |

---

## 2. `FACT_WEATHER`

Weather observations associated with a station and observation time.

Grain: A row is added for every update we get from the weather api.

| Variable | Type | Description |
|---|---|---|
| `weather_key` | INTEGER (PK) | Unique weather fact key |
| `observed_at` | TIMESTAMPTZ | Time when the weather was observed |
| `station_name` | VARCHAR | Name of the weather station |
| `temperature_c` | NUMERIC | Temperature in degrees Celsius |
| `precipitation_mm` | NUMERIC | Precipitation in millimetres |
| `visibility_km` | NUMERIC | Visibility in kilometres |
| `wind_speed_ms` | NUMERIC | Wind speed in metres per second |
| `wind_speed_max_ms` | NUMERIC | Maximum wind speed in metres per second |
| `weather_category` | VARCHAR | Categorized weather condition |

---

# Dimensions

## 3. `DIM_DATE`

Calendar attributes used to group performance records by date.

| Variable | Type | Description |
|---|---|---|
| `date_key` | INTEGER (PK) | Unique date key |
| `full_date` | DATE | Calendar date |
| `year` | INTEGER | Calendar year |
| `month` | INTEGER | Month number |
| `weekday_nr` | INTEGER | Numeric day-of-week value |
| `weekday` | VARCHAR | Day of week |
| `is_weekend` | BOOLEAN | Indicates whether the date falls on a weekend |
| `is_holiday` | BOOLEAN | Indicates whether the date is a public holiday |

## 4. `DIM_TIME`

Time attributes used to group performance records by time of day.

| Variable | Type | Description |
|---|---|---|
| `time_key` | INTEGER (PK) | Unique time key |
| `hour` | INTEGER | Hour component of the time |
| `minute` | INTEGER | Minute component of the time |
| `time_of_day` | VARCHAR | Named time-of-day category |
| `is_peak_hour` | BOOLEAN | Indicates whether the time is during a peak period |

## 5. `DIM_ROUTE`

A table of all routes in the Tartu bus network.

| Variable | Type | Description |
|---|---|---|
| `route_key` | INTEGER (PK) | Unique route dimension key |
| `route_id` | VARCHAR | Unique route identifier |
| `short_name` | VARCHAR | Public transport line number |
| `long_name` | VARCHAR | Route name |
| `mode` | VARCHAR | Transport mode |

## 6. `DIM_TRIP`

All trips taking place on all routes, where foreign route_key connects to the specific route on DIM_ROUTE

| Variable | Type | Description |
|---|---|---|
| `trip_key` | INTEGER (PK) | Unique trip dimension key |
| `trip_id` | VARCHAR | Unique trip identifier |
| `route_key` | INTEGER (FK) | Reference to the route dimension |
| `service_id` | VARCHAR | Service and calendar identifiers |
| `trip_headsign` | VARCHAR | Trip start and destination |
| `shape_id` | VARCHAR | Geographic route shape identifier |
| `stop_count` | INTEGER | Total number of stops in the trip |

## 7. `DIM_STOP`

A table of all bus stops in the Tartu bus network.

| Variable | Type | Description |
|---|---|---|
| `stop_key` | INTEGER (PK) | Unique stop dimension key |
| `stop_id` | VARCHAR | Unique stop identifier |
| `stop_code` | VARCHAR | Stop code |
| `stop_name` | VARCHAR | Stop name |
| `latitude` | NUMERIC | Stop latitude |
| `longitude` | NUMERIC | Stop longitude |
| `district` | VARCHAR | Administrative district containing the stop |
| `valid_from` | TIMESTAMPTZ | Start of the stop record validity period |
| `valid_to` | TIMESTAMPTZ | End of the stop record validity period |
| `is_current` | BOOLEAN | Indicates whether this is the current stop version |

# Staging Tables

## 8. `STAGING_BUS_LIVE`

Raw realtime observations of buses that is updated about every 5 seconds.

| Variable | Type | Description |
|---|---|---|
| `snapshot_id` | BIGSERIAL | Unique realtime observation ID |
| `update_time` | TIMESTAMPTZ | Time of the reported observation |
| `device_id` | VARCHAR | Bus device identifier |
| `location_id` | VARCHAR | Vehicle identifier (usually the plate nr) |
| `trip_id` | VARCHAR | Current trip identifier |
| `line_nr` | VARCHAR | Public transport line number |
| `line_dir` | INTEGER | Direction identifier for the line |
| `line_name` | VARCHAR | Route name |
| `longitude` | DOUBLE PRECISION | Geographic longitude of the Bus |
| `latitude` | DOUBLE PRECISION | Geographic latitude of the Bus |
| `bearing` | DOUBLE PRECISION | Bus heading in degrees |
| `speed` | DOUBLE PRECISION | Bus speed |
| `start_time` | TIME | Real trip start time |
| `start_date` | DATE | Real trip start date |

## 9. `STAGING_BUS_SCHEDULE`

Raw scheduled trip and stop data, to get the stop times.

| Variable | Type | Description |
|---|---|---|
| `trip_id` | VARCHAR | Current trip identifier |
| `route_id` | VARCHAR | Associated route |
| `service_id` | VARCHAR | Service and calendar identifiers |
| `trip_headsign` | VARCHAR | Trip start and destination |
| `shape_id` | VARCHAR | Geographic route shape identifier |
| `stop_id` | VARCHAR | Current bus stop identifier |
| `stop_code` | VARCHAR | Stop code |
| `stop_name` | VARCHAR | Name of the bus stop |
| `stop_sequence` | INTEGER | Position of the stop within the trip |
| `scheduled_arrival` | TIMESTAMPTZ | Scheduled arrival time at the stop |
| `scheduled_departure` | TIMESTAMPTZ | Scheduled departure time from the stop |
| `service_date` | DATE | Date on which the scheduled service operates |

