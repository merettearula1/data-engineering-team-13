-- Silver: current bus stops
-- bronze.raw_events (daily snapshot, list of stops) -> one row per stop ever seen (latest version).
-- History is kept by the gold snapshot snap_stops, not here.

WITH snapshots AS (
    SELECT
        id                                    AS bronze_id,
        (payload->>'fetched_at')::timestamptz AS fetched_at,
        payload->'payload'                    AS stops
    FROM {{ source('bronze', 'raw_events') }}
    WHERE source_name = 'bus_stops'
),

stops AS (
    SELECT
        l.bronze_id,
        l.fetched_at,
        s->>'id'             AS stop_id,
        s->>'code'           AS stop_code,
        s->>'name'           AS stop_name,
        (s->>'lat')::numeric AS latitude,
        (s->>'lon')::numeric AS longitude
    FROM snapshots AS l,
         jsonb_array_elements(l.stops) AS s
),

ranked AS (
    -- keep the most recently seen version of each stop
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY stop_id ORDER BY fetched_at DESC, bronze_id DESC) AS copy_nr
    FROM stops
    WHERE stop_id IS NOT NULL
)

SELECT
    stop_id,
    stop_code,
    stop_name,
    latitude,
    longitude,
    NULL::text AS district      -- the stops API has no district; gold dim_stop derives it from lat/lon
FROM ranked
WHERE copy_nr = 1