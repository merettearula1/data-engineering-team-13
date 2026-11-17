-- Silver: bus routes (SCD1): one row per route_id, latest version, including routes no longer listed
WITH snapshots AS (
    SELECT id AS bronze_id,
           (payload->>'fetched_at')::timestamptz AS fetched_at,
           payload->'payload' AS routes
    FROM {{ source('bronze', 'raw_events') }}
    WHERE source_name = 'bus_routes'
      AND jsonb_typeof(payload->'payload') = 'array'   -- skip error responses
),
routes AS (
    SELECT s.bronze_id, s.fetched_at,
           r->>'id'        AS route_id,
           r->>'shortName' AS short_name,
           r->>'longName'  AS long_name,
           r->>'mode'      AS mode
    FROM snapshots AS s, jsonb_array_elements(s.routes) AS r
),
ranked AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY route_id ORDER BY fetched_at DESC, bronze_id DESC) AS copy_nr
    FROM routes
    WHERE route_id IS NOT NULL
)
SELECT route_id, short_name, long_name, mode
FROM ranked
WHERE copy_nr = 1