-- =====================================================================
-- Project 1: Tartu bus punctuality vs weather - star schema (PostgreSQL)

-- Grain of fact_bus_performance:
--   Each row represents 1 trip at 1 stop position (stop_index) on 1 service date.
--   Stop_index is part of the grain because loop routes (e.g. lines 5, 22, 31R) visit 
--   the same stop twice on one trip.
-- On-time rule: |arrival_delay_sec| <= 180 (+/- 3 min) -> on time, otherwise disrupted.
-- =====================================================================

-- development only: makes the script re-runnable
DROP SCHEMA IF EXISTS dwh CASCADE;
DROP SCHEMA IF EXISTS staging CASCADE;
CREATE SCHEMA dwh;
SET search_path TO dwh;

-- DIMENSIONS

-- dim_date: STATIC
CREATE TABLE dim_date (
    date_key    INTEGER     PRIMARY KEY,        -- YYYYMMDD, e.g. 20261005
    full_date   DATE        NOT NULL UNIQUE,
    year        INTEGER    NOT NULL,
    month       INTEGER    NOT NULL,
    weekday     VARCHAR(10) NOT NULL,           -- 'Monday' ...
    weekday_nr  INTEGER    NOT NULL,           -- ISO 1 = Monday ... 7 = Sunday (for sorting)
    is_weekend  BOOLEAN     NOT NULL,
    is_holiday  BOOLEAN     NOT NULL DEFAULT FALSE
);

-- dim_time: STATIC
CREATE TABLE dim_time (
    time_key      INTEGER     PRIMARY KEY,      -- HHMM, e.g. 815 = 08:15
    hour          INTEGER    NOT NULL CHECK (hour BETWEEN 0 AND 23),
    minute        INTEGER    NOT NULL CHECK (minute BETWEEN 0 AND 59),
    time_of_day   VARCHAR(20) NOT NULL,         -- night / morning_peak / daytime / evening_peak / evening
    is_peak_hour  BOOLEAN     NOT NULL
);

-- fact_weather: (second fact table)
-- Grain: each row represents 1 weather observation at 1 station at 1 point in time (every 10-60 min).
-- Shares dim_date and dim_time with fact_bus_performance (conformed dimensions).
CREATE TABLE fact_weather (
    weather_key        SERIAL        PRIMARY KEY,
    date_key           INTEGER       NOT NULL REFERENCES dim_date(date_key),   -- local date of the observation
    time_key           INTEGER       NOT NULL REFERENCES dim_time(time_key),   -- minute of the observation
    station_name       VARCHAR(100)  NOT NULL,
    observed_at        TIMESTAMPTZ   NOT NULL,
    precipitation_mm   NUMERIC(6,2),
    visibility_km      NUMERIC(6,2),
    temperature_c      NUMERIC(5,2),
    wind_speed_ms      NUMERIC(5,2),
    wind_speed_max_ms  NUMERIC(5,2),
    weather_category   VARCHAR(20)   NOT NULL,  -- derived from 'phenomenon': clear / rain / snow / fog / other
    UNIQUE (station_name, observed_at)
);
CREATE INDEX ix_weather_date_time ON fact_weather (date_key, time_key);

-- dim_route: SCD TYPE 1
CREATE TABLE dim_route (
    route_key    SERIAL       PRIMARY KEY,
    route_id     VARCHAR(50)  NOT NULL UNIQUE,  -- e.g. '1:3_1762_1_3' (one route id = one direction)
    short_name   VARCHAR(20)  NOT NULL,         -- line number; NOT unique (2 directions share it)
    long_name    VARCHAR(200),
    mode         VARCHAR(20)
);

-- dim_trip: SCD TYPE 1
CREATE TABLE dim_trip (
    trip_key       SERIAL       PRIMARY KEY,
    trip_id        VARCHAR(300) NOT NULL UNIQUE,   -- real tripIds are ~150 chars
    service_id     VARCHAR(50),
    trip_headsign  VARCHAR(200)
);

-- dim_stop: SCD TYPE 2 (history kept with valid_from / valid_to)
CREATE TABLE dim_stop (
    stop_key    SERIAL        PRIMARY KEY,      -- new key for every version of a stop
    stop_id     VARCHAR(50)   NOT NULL,
    stop_code   VARCHAR(20),
    stop_name   VARCHAR(200)  NOT NULL,
    latitude    NUMERIC(9,6)  NOT NULL,
    longitude   NUMERIC(9,6)  NOT NULL,
    district    VARCHAR(100),                   -- linnaosa, derived from lat/lon in ETL
    valid_from  TIMESTAMPTZ   NOT NULL DEFAULT '1900-01-01',
    valid_to    TIMESTAMPTZ   NOT NULL DEFAULT '9999-12-31',
    is_current  BOOLEAN       NOT NULL DEFAULT TRUE,
    UNIQUE (stop_id, valid_from)
);
CREATE UNIQUE INDEX ux_dim_stop_current ON dim_stop (stop_id) WHERE is_current;

-- FACT TABLE
CREATE TABLE fact_bus_performance (
    performance_key      BIGSERIAL    PRIMARY KEY,

    date_key             INTEGER      NOT NULL REFERENCES dim_date(date_key),      -- service date
    route_key            INTEGER      NOT NULL REFERENCES dim_route(route_key),
    trip_key             INTEGER      NOT NULL REFERENCES dim_trip(trip_key),
    stop_key             INTEGER      NOT NULL REFERENCES dim_stop(stop_key),
    weather_key          INTEGER               REFERENCES fact_weather(weather_key), -- nearest weather observation in time (fact-to-fact link)
    time_key             INTEGER      NOT NULL REFERENCES dim_time(time_key),      -- scheduled arrival, minute

    scheduled_arrival    TIMESTAMPTZ,
    scheduled_departure  TIMESTAMPTZ,
    realtime_arrival     TIMESTAMPTZ,
    realtime_departure   TIMESTAMPTZ,

    -- measures from the stoptimes API
    arrival_delay_sec    INTEGER,                        -- negative = early
    departure_delay_sec  INTEGER,

    -- API field 'realtime': FALSE = only the timetable, the bus has no live prediction yet
    -- (the API then returns delay 0 as a placeholder, which is NOT a measurement)
    is_realtime          BOOLEAN      NOT NULL DEFAULT FALSE,

    -- on time = within +/- 3 minutes (early or late); disrupted = on_time_flag FALSE.
    -- NULL when there is no real-time data.
    on_time_flag         BOOLEAN GENERATED ALWAYS AS
                           (CASE WHEN is_realtime THEN ABS(arrival_delay_sec) <= 180 END) STORED,

    observation_time     TIMESTAMPTZ  NOT NULL DEFAULT now(),  -- when the row was pulled from the API

    -- measures aggregated from the live GPS feed (120 sec before arrival)
    avg_speed_kmh        NUMERIC(6,2),
    gps_ping_count       INTEGER,

    is_canceled          BOOLEAN      NOT NULL DEFAULT FALSE,
    stop_index           INTEGER     NOT NULL,          -- position of the stop on the trip

    CONSTRAINT uq_fact_grain UNIQUE (date_key, trip_key, stop_index),
    -- data quality rule: schedule-only rows must not carry placeholder delays
    CONSTRAINT chk_delay_only_if_realtime
        CHECK (is_realtime OR (arrival_delay_sec IS NULL AND departure_delay_sec IS NULL))
);

CREATE INDEX ix_fact_date    ON fact_bus_performance (date_key);
CREATE INDEX ix_fact_time    ON fact_bus_performance (time_key);
CREATE INDEX ix_fact_route   ON fact_bus_performance (route_key);
CREATE INDEX ix_fact_stop    ON fact_bus_performance (stop_key);
CREATE INDEX ix_fact_weather ON fact_bus_performance (weather_key);

-- DML (Data Manipulation Language): fill the rows in the static dimensions
INSERT INTO dim_date
SELECT to_char(d, 'YYYYMMDD')::INT,
       d::DATE,
       EXTRACT(YEAR FROM d),
       EXTRACT(MONTH FROM d),
       trim(to_char(d, 'Day')),
       EXTRACT(ISODOW FROM d),
       EXTRACT(ISODOW FROM d) IN (6, 7),
       to_char(d, 'MM-DD') IN ('01-01','02-24','05-01','06-23','06-24','08-20','12-24','12-25','12-26')
       -- moving holidays (Suur Reede, Ülestõusmispühade 1. püha) must be added by hand
FROM generate_series('2026-01-01'::DATE, '2027-12-31'::DATE, INTERVAL '1 day') AS d;

INSERT INTO dim_time
SELECT (m / 60) * 100 + (m % 60),
       m / 60,
       m % 60,
       CASE WHEN m / 60 BETWEEN 6  AND 8  THEN 'morning_peak'
            WHEN m / 60 BETWEEN 9  AND 14 THEN 'daytime'
            WHEN m / 60 BETWEEN 15 AND 17 THEN 'evening_peak'
            WHEN m / 60 BETWEEN 18 AND 22 THEN 'evening'
            ELSE 'night' END,
       (m / 60) IN (6, 7, 8, 15, 16, 17)
FROM generate_series(0, 1439) AS m;

-- Sample rows (illustration only; the route is a real entry from /v1/routes,
-- the stop, weather reading and delay are invented)
INSERT INTO dim_route (route_id, short_name, long_name, mode)
VALUES ('1:3_1762_1_3', '3', 'Nõlvaku - Zoomeedikum', 'BUS');

INSERT INTO dim_trip (trip_id, service_id, trip_headsign)
VALUES ('T-1001', 'WEEKDAY', 'Zoomeedikum');

INSERT INTO dim_stop (stop_id, stop_code, stop_name, latitude, longitude, district)
VALUES ('S-100', '0100', 'Vanemuise', 58.3776, 26.7290, 'Kesklinn');

INSERT INTO fact_weather (date_key, time_key, station_name, observed_at, precipitation_mm, visibility_km,
                          temperature_c, wind_speed_ms, wind_speed_max_ms, weather_category)
VALUES (20261005, 800, 'Tartu-Tõravere', '2026-10-05 08:00+03', 0.4, 9.5, 6.2, 3.1, 5.0, 'rain');

INSERT INTO fact_bus_performance
    (date_key, time_key, route_key, trip_key, stop_key, weather_key, stop_index,
     scheduled_arrival, scheduled_departure, realtime_arrival, realtime_departure,
     arrival_delay_sec, departure_delay_sec, is_realtime)
VALUES
    (20261005, 815, 1, 1, 1, 1, 7,
     '2026-10-05 08:15+03', '2026-10-05 08:15+03',
     '2026-10-05 08:19+03', '2026-10-05 08:19+03',
     240, 240, TRUE);   -- 4 min late -> on_time_flag = FALSE

-- STAGING (not part of the star schema): raw live GPS pings, ~1 row / 5 s
CREATE SCHEMA staging;

CREATE TABLE staging.bus_live_raw (
    snapshot_id  BIGSERIAL PRIMARY KEY,
    update_time  TIMESTAMPTZ,
    device_id    VARCHAR,
    location_id  VARCHAR,
    trip_id      VARCHAR,
    line_nr      VARCHAR,
    line_dir     INTEGER,
    line_name    VARCHAR,
    longitude    DOUBLE PRECISION,
    latitude     DOUBLE PRECISION,
    bearing      DOUBLE PRECISION,
    speed        DOUBLE PRECISION,
    start_time   TIME,
    start_date   DATE
);
CREATE INDEX ix_live_trip_time ON staging.bus_live_raw (trip_id, start_date, update_time);

-- ETL step: enrich each stop event with the bus speed on approach
-- (120 sec before real arrival). If the API speed is m/s, use l.speed * 3.6.
UPDATE dwh.fact_bus_performance f
SET avg_speed_kmh  = s.avg_speed,
    gps_ping_count = s.n
FROM (
    SELECT fe.performance_key,
           AVG(l.speed) AS avg_speed,
           COUNT(*)     AS n
    FROM dwh.fact_bus_performance fe
    JOIN dwh.dim_trip t ON t.trip_key = fe.trip_key
    JOIN dwh.dim_date d ON d.date_key = fe.date_key
    JOIN staging.bus_live_raw l
      ON l.trip_id    = t.trip_id
     AND l.start_date = d.full_date
     AND l.update_time BETWEEN fe.realtime_arrival - INTERVAL '120 seconds'
                           AND fe.realtime_arrival
    WHERE fe.realtime_arrival IS NOT NULL
    GROUP BY fe.performance_key
) s
WHERE f.performance_key = s.performance_key;
