-- Silver: stop events. One row = one stop of one trip on one service date, as seen in one poll.
-- Not unique per stop: gold picks the latest real-time observation per (service_date, trip_id, stop_index).
WITH responses AS (
    SELECT id                                    AS bronze_id,
           (payload->>'fetched_at')::timestamptz AS observation_time,
           payload->>'trip_id'                   AS trip_id,
           payload->'payload'                    AS stop_times
    FROM {{ source('bronze', 'raw_events') }}
    WHERE source_name = 'bus_trip_stop_times'
      AND jsonb_typeof(payload->'payload') = 'array'   -- empty lists simply give no rows
),
stop_times AS (
    SELECT r.bronze_id, r.observation_time,
           COALESCE(st->>'tripId', r.trip_id)       AS trip_id,
           st->>'stopId'                            AS stop_id,
           (st->>'stopIndex')::integer              AS stop_index,
           (st->>'scheduledArrival')::timestamptz   AS scheduled_arrival,
           (st->>'scheduledDeparture')::timestamptz AS scheduled_departure,
           (st->>'realtimeArrival')::timestamptz    AS realtime_arrival,
           (st->>'realtimeDeparture')::timestamptz  AS realtime_departure,
           (st->>'arrivalDelay')::integer           AS arrival_delay_sec,
           (st->>'departureDelay')::integer         AS departure_delay_sec,
           (st->>'realtime')::boolean               AS is_realtime,
           (st->>'canceled')::boolean               AS is_canceled,
           st->>'headsign'                          AS headsign
    FROM responses AS r, jsonb_array_elements(r.stop_times) AS st
),
with_service_date AS (
    -- service day = local date of the trip's earliest scheduled time in this response
    SELECT *,
           (MIN(COALESCE(scheduled_departure, scheduled_arrival)) OVER (PARTITION BY bronze_id)
               AT TIME ZONE 'Europe/Tallinn')::date AS service_date
    FROM stop_times
),
ranked AS (
    -- a reloaded file repeats the same poll: keep one copy
    SELECT *, ROW_NUMBER() OVER (
               PARTITION BY service_date, trip_id, stop_index, observation_time
               ORDER BY bronze_id DESC) AS copy_nr
    FROM with_service_date
    WHERE trip_id IS NOT NULL
)
SELECT
    e.service_date,
    e.trip_id,
    t.route_id,                                   -- from bus_trips via silver_trips
    e.stop_id,
    e.stop_index,
    e.scheduled_arrival,
    e.scheduled_departure,
    e.realtime_arrival,
    e.realtime_departure,
    e.arrival_delay_sec,
    e.departure_delay_sec,
    e.is_realtime,
    e.is_canceled,
    e.observation_time,
    t.service_id,
    COALESCE(e.headsign, t.trip_headsign)         AS trip_headsign
FROM ranked AS e
LEFT JOIN {{ ref('silver_trips') }} AS t
       ON t.trip_id = e.trip_id
WHERE e.copy_nr = 1