-- Silver: current bus stops
-- bronze.raw_events (daily snapshot, list of stops) -> one row per stop in the LATEST snapshot.
-- History is kept by the gold snapshot snap_stops, not here.

WITH snapshots AS (
    SELECT
        id                                    AS bronze_id,
        (payload->>'fetched_at')::timestamptz AS fetched_at,
        payload->'payload'                    AS stops
    FROM {{ source('bronze', 'raw_events') }}
    WHERE source_name = 'bus_stops'
),

latest AS (
    -- only the newest snapshot: a stop missing from it counts as removed
    SELECT *
    FROM snapshots
    WHERE fetched_at = (SELECT max(fetched_at) FROM snapshots)
),

stops AS (
    SELECT
        l.bronze_id,
        s->>'id'             AS stop_id,
        s->>'code'           AS stop_code,
        s->>'name'           AS stop_name,
        (s->>'lat')::numeric AS latitude,
        (s->>'lon')::numeric AS longitude
    FROM latest AS l,
         jsonb_array_elements(l.stops) AS s
),

ranked AS (
    -- a reloaded file repeats the snapshot: keep one copy per stop
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY stop_id ORDER BY bronze_id DESC) AS copy_nr
    FROM stops
    WHERE stop_id IS NOT NULL
)

SELECT
    stop_id,
    stop_code,
    stop_name,
    latitude,
    longitude,
    NULL::text AS district      -- the stops API has no district
FROM ranked
WHERE copy_nr = 1