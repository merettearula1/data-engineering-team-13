-- Silver: trip -> route lookup. One row per trip_id ever seen (old stop events still need their route).
WITH polls AS (
    SELECT id AS bronze_id,
           (payload->>'fetched_at')::timestamptz AS fetched_at,
           payload->>'route_id' AS route_id,          -- the route this poll asked about
           payload->'payload'   AS trips
    FROM {{ source('bronze', 'raw_events') }}
    WHERE source_name = 'bus_trips'
      AND jsonb_typeof(payload->'payload') = 'array'
),
trips AS (
    SELECT p.bronze_id, p.fetched_at, p.route_id,
           t->>'id'           AS trip_id,
           t->>'serviceId'    AS service_id,
           t->>'tripHeadsign' AS trip_headsign
    FROM polls AS p, jsonb_array_elements(p.trips) AS t
),
ranked AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY trip_id ORDER BY fetched_at DESC, bronze_id DESC) AS copy_nr
    FROM trips
    WHERE trip_id IS NOT NULL
)
SELECT trip_id, route_id, service_id, trip_headsign
FROM ranked
WHERE copy_nr = 1