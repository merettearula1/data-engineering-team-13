{{ config(
    materialized = 'table',
    indexes = [{'columns': ['trip_id', 'service_date', 'update_time']}]
) }}
-- Silver: GPS status updates. One row per trip x service date x update time.
-- Speed: the API's own 'speed' field barely tracks real movement (correlation ~0.3 with the
-- distance actually covered between pings), so we also keep the coordinates and derive the
-- distance driven since the trip's previous ping. Gold computes speed as distance / time.
WITH messages AS (
    SELECT id AS bronze_id, payload->'payload' AS vehicles
    FROM {{ source('bronze', 'raw_events') }}
    WHERE source_name = 'bus_live'
      AND jsonb_typeof(payload->'payload') = 'array'
),
positions AS (
    SELECT m.bronze_id,
           '1:' || (v->'trip'->>'tripId')                 AS trip_id,       -- see check below
           to_date(v->'trip'->>'startDate', 'YYYYMMDD')   AS service_date,  -- service day, not clock day
           (v->>'updateTime')::timestamptz                AS update_time,
           (v->'position'->>'latitude')::numeric          AS latitude,
           (v->'position'->>'longitude')::numeric         AS longitude,
           (v->'position'->>'speed')::numeric * 3.6       AS speed_kmh      -- API-reported, m/s -> km/h
    FROM messages AS m, jsonb_array_elements(m.vehicles) AS v
    WHERE v->'trip'->>'tripId' IS NOT NULL                                   -- vehicles not on a trip
),
ranked AS (
    -- consecutive messages repeat a vehicle's last status: keep one copy
    SELECT *, ROW_NUMBER() OVER (PARTITION BY trip_id, service_date, update_time ORDER BY bronze_id DESC) AS copy_nr
    FROM positions
),
deduped AS (
    SELECT trip_id, service_date, update_time, latitude, longitude, speed_kmh
    FROM ranked
    WHERE copy_nr = 1
),
with_previous AS (
    SELECT
        *,
        LAG(update_time) OVER w AS prev_update_time,
        LAG(latitude)    OVER w AS prev_latitude,
        LAG(longitude)   OVER w AS prev_longitude
    FROM deduped
    WINDOW w AS (PARTITION BY trip_id, service_date ORDER BY update_time)
),
measured AS (
    SELECT
        *,
        EXTRACT(EPOCH FROM update_time - prev_update_time)::numeric AS seconds_since_prev,
        -- Equirectangular distance in metres: 1 degree latitude = 111 320 m, longitude scaled by
        -- cos(58.38 deg) = 0.5243 at Tartu's latitude. Accurate to well under 1% at these distances.
        111320 * SQRT(
            POWER(latitude - prev_latitude, 2)
            + POWER((longitude - prev_longitude) * 0.5243, 2)
        ) AS raw_distance_m
    FROM with_previous
)
SELECT
    trip_id,
    service_date,
    update_time,
    latitude,
    longitude,
    speed_kmh,
    prev_update_time,
    seconds_since_prev,
    -- GPS jumps implying more than 100 km/h (27.8 m/s) are glitches: no distance for that step.
    CASE
        WHEN seconds_since_prev > 0
         AND raw_distance_m / seconds_since_prev <= 27.8
        THEN ROUND(raw_distance_m, 1)
    END AS distance_m
FROM measured
