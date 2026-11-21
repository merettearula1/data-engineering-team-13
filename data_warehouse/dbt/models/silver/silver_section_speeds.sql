{{ config(materialized = 'table') }}
-- Silver: running speed on the road section driven TO each stop of a realtime trip.
-- One row = one (service_date, trip_id, stop_index) whose section from the previous stop has GPS coverage.
--
-- The API's realtime_arrival is a forecast made minutes earlier (the GPS passes the stop a median
-- ~1 min later), so it cannot delimit the driving. Instead the GPS track says when the bus was
-- actually at each stop: arrived = first ping within 50 m of the stop, departed = last ping within
-- 50 m, searched within 15 minutes of the forecast. Speed = GPS distance driven / time between
-- departing the previous stop and arriving at this one, so time standing at the stops is excluded.
-- The API's own 'speed' field is not used: it barely tracks real movement (see silver_live_positions).

WITH ranked_events AS (
    -- same pick as gold fact_bus_performance: latest realtime observation per stop of a trip run
    SELECT
        e.*,
        ROW_NUMBER() OVER (
            PARTITION BY e.service_date, e.trip_id, e.stop_index
            ORDER BY COALESCE(e.is_realtime, false) DESC,
                     e.observation_time DESC NULLS LAST
        ) AS rn
    FROM {{ ref('silver_stop_events') }} e
    WHERE e.service_date IS NOT NULL
      AND e.trip_id IS NOT NULL
      AND e.stop_index IS NOT NULL
),
realtime_events AS (
    SELECT e.service_date, e.trip_id, e.stop_index, e.realtime_arrival, s.latitude, s.longitude
    FROM ranked_events e
    JOIN {{ ref('silver_stops') }} s ON s.stop_id = e.stop_id
    WHERE e.rn = 1
      AND e.is_realtime
      AND e.realtime_arrival IS NOT NULL
),
stop_passes AS (
    -- when the GPS track was actually at the stop
    SELECT
        e.service_date,
        e.trip_id,
        e.stop_index,
        p.arrived_at,
        p.departed_at
    FROM realtime_events e
    CROSS JOIN LATERAL (
        SELECT
            MIN(l.update_time) AS arrived_at,
            MAX(l.update_time) AS departed_at
        FROM {{ ref('silver_live_positions') }} l
        WHERE l.trip_id = e.trip_id
          AND l.service_date = e.service_date
          AND l.update_time BETWEEN e.realtime_arrival - INTERVAL '15 minutes'
                                AND e.realtime_arrival + INTERVAL '15 minutes'
          -- equirectangular metres (see silver_live_positions)
          AND 111320 * SQRT(
                  POWER(l.latitude - e.latitude, 2)
                  + POWER((l.longitude - e.longitude) * 0.5243, 2)
              ) <= 50
    ) p
    WHERE p.arrived_at IS NOT NULL
),
sections AS (
    -- road section driven to each stop: from departing the previous stop to arriving at this one
    SELECT
        p.*,
        LAG(p.stop_index)  OVER run AS prev_stop_index,
        LAG(p.departed_at) OVER run AS prev_departed_at
    FROM stop_passes p
    WINDOW run AS (PARTITION BY p.service_date, p.trip_id ORDER BY p.stop_index)
)
SELECT
    sec.service_date,
    sec.trip_id,
    sec.stop_index,
    sec.prev_departed_at                         AS departed_prev_stop_at,
    sec.arrived_at                               AS arrived_at,
    SUM(l.distance_m)                            AS distance_m,
    SUM(l.seconds_since_prev)                    AS driving_seconds,
    -- under 15 s of GPS coverage is too little to call a speed
    CASE
        WHEN SUM(l.seconds_since_prev) >= 15
        THEN ROUND(3.6 * SUM(l.distance_m) / SUM(l.seconds_since_prev), 2)
    END                                          AS speed_kmh,
    COUNT(*)::integer                            AS gps_step_count
FROM sections sec
-- only ping-to-ping steps lying fully inside the section
JOIN {{ ref('silver_live_positions') }} l
  ON l.trip_id = sec.trip_id
 AND l.service_date = sec.service_date
 AND l.prev_update_time >= sec.prev_departed_at
 AND l.update_time <= sec.arrived_at
 AND l.distance_m IS NOT NULL
WHERE sec.prev_stop_index = sec.stop_index - 1      -- truly consecutive stops
  AND sec.arrived_at > sec.prev_departed_at
GROUP BY sec.service_date, sec.trip_id, sec.stop_index, sec.prev_departed_at, sec.arrived_at
