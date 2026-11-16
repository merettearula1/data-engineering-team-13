{{ config(
    materialized = 'table',
    indexes = [{'columns': ['trip_id', 'service_date', 'update_time']}]
) }}
-- Silver: GPS status updates. One row per trip x service date x update time.
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
           (v->'position'->>'speed')::numeric * 3.6       AS speed_kmh      -- m/s -> km/h
    FROM messages AS m, jsonb_array_elements(m.vehicles) AS v
    WHERE v->'trip'->>'tripId' IS NOT NULL                                   -- vehicles not on a trip
),
ranked AS (
    -- consecutive messages repeat a vehicle's last status: keep one copy
    SELECT *, ROW_NUMBER() OVER (PARTITION BY trip_id, service_date, update_time ORDER BY bronze_id DESC) AS copy_nr
    FROM positions
)
SELECT trip_id, service_date, update_time, speed_kmh
FROM ranked
WHERE copy_nr = 1