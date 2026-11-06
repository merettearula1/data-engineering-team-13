-- =====================================================================
-- Q1: On which bus lines is the average delay (in seconds) greatest during adverse weather conditions (weather phenomena) or heavy rainfall compared to clear weather?
-- =====================================================================
-- Categorises official Estonian weather phenomena into Heavy/Adverse vs Baseline (Clear/Light clouds).
-- ---------------------------------------------------------------------
WITH weather_phenomena_classified AS (
    SELECT
        weather_key,
        weather_category,
        precipitation_mm,
        
        -- Mapping official Estonian Estonian/English weather phenomena
        CASE 
            -- GROUP 1: Heavy Rain & High-Intensity Showers
            WHEN weather_category IN ('Heavy rain', 'Heavy shower', 'Tugev vihm', 'Tugev hoovihm')
              OR precipitation_mm >= 2.5
            THEN 'Heavy Rain / Heavy Shower'
            
            -- GROUP 2: General Adverse Weather: Snow, Sleet, Glaze/Ice, Fog, Hail, Rain
            WHEN weather_category IN (
                -- Winter Conditions: Snow, Sleet & Hail
                'Light snow shower', 'Moderate snow shower', 'Heavy snow shower',
                'Nõrk hooglumi', 'Mõõdukas hooglumi', 'Tugev hooglumi',
                'Light snowfall', 'Moderate snowfall', 'Heavy snowfall',
                'Nõrk lumesadu', 'Mõõdukas lumesadu', 'Tugev lumesadu',
                'Light sleet', 'Moderate sleet', 'Nõrk lörtsisadu', 'Mõõdukas lörtsisadu',
                -- Visibility & Road Surface Hazards: Ice, Glaze & Fog
                'Glaze', 'Jäide', 'Fog', 'Udu', 'Mist', 'Uduvine', 'Hail', 'Rahe',
                
                -- Standard / Moderate Rain & Light Showers
                'Light rain', 'Moderate rain', 'Nõrk vihm', 'Mõõdukas vihm',
                'Light shower', 'Moderate shower', 'Nõrk hoovihm', 'Mõõdukas hoovihm'
            )
            THEN 'Adverse Weather (Snow/Fog/Ice/Rain)'
            
            -- GROUP 3: Clear / Ideal Operating Conditions (Baseline)
            WHEN weather_category IN (
                'Clear', 'Selge', 
                'Few clouds', 'Vähene pilvisus', 
                'Variable clouds', 'Poolpilves'
            )
            AND (precipitation_mm IS NULL OR precipitation_mm < 0.1)
            THEN 'Clear / Good Weather'
            -- FALLBACK GROUP: Overcast, general cloudiness, or uncategorized weather events.
            ELSE 'Overcast / Other'
        END AS weather_condition_group
    FROM dwh.dim_weather
),

-- ---------------------------------------------------------------------
-- Join performance facts with routes and classified weather groups. 
-- Aggregate key metrics (ping count, average delay, disruption rate) grouped by bus line and weather category.
-- ---------------------------------------------------------------------
line_weather_performance AS (
    SELECT
        r.short_name AS bus_line,
        w.weather_condition_group,
        
        -- Total live stop arrival pings observed under this condition
        COUNT(*) AS total_stop_observations,
        
        -- Mean arrival delay in seconds across all pings for the line/weather pair
        ROUND(AVG(f.arrival_delay_sec), 2) AS avg_arrival_delay_sec,
        
        -- % of arrivals outside the punctuality buffer (on_time_flag = FALSE)
        -- Captures both severe delays (>3 min late) and premature departures (>3 min early)
        ROUND(100.0 * COUNT(*) FILTER (WHERE f.on_time_flag = FALSE) / COUNT(*), 2) AS disruption_rate_pct

    FROM dwh.fact_bus_performance f
    JOIN dwh.dim_route r 
      ON f.route_key = r.route_key
    JOIN weather_phenomena_classified w 
      ON f.weather_key = w.weather_key

    -- Excludes static schedule fallback records (delay = 0 placeholders).
    WHERE f.is_realtime = TRUE
    -- Restrict to our 3 core comparison buckets, excluding 'Overcast / Other'.
      AND w.weather_condition_group IN (
          'Heavy Rain / Heavy Shower', 
          'Adverse Weather (Snow/Fog/Ice/Rain)', 
          'Clear / Good Weather'
      )

    GROUP BY 
        r.short_name,
        w.weather_condition_group

    -- Ensures a line must have at least 30 observations under a specific weather condition to prevent rare edge cases or single noisy runs from biasing averages.
    HAVING COUNT(*) >= 30
)
  
-- ---------------------------------------------------------------------
-- Pivot rows into line-level columns using conditional aggregation (MAX + CASE) to compare clear baseline metrics side-by-side with adverse weather metrics.
-- ---------------------------------------------------------------------
SELECT
    bus_line,
    
    -- Baseline: Average delay (seconds) during Clear / Good Weather
    MAX(CASE WHEN weather_condition_group = 'Clear / Good Weather' 
             THEN avg_arrival_delay_sec END) AS avg_delay_clear_sec,
    
    -- Severe & adverse: Average delay (seconds) during severe and adverse conditions
    MAX(CASE WHEN weather_condition_group = 'Heavy Rain / Heavy Shower' 
             THEN avg_arrival_delay_sec END) AS avg_delay_heavy_rain_sec,
             
    MAX(CASE WHEN weather_condition_group = 'Adverse Weather (Snow/Fog/Ice/Rain)' 
             THEN avg_arrival_delay_sec END) AS avg_delay_adverse_sec,
    
    -- Delta: delay under heavy rainfall - delay under good weather
    -- "Heavy rain delay penalty": Incremental delay added by heavy rainfall over the clear weather baseline.
    -- High values pinpoint lines where route geometry or traffic corridors degrade under rain.
    ROUND(
        MAX(CASE WHEN weather_condition_group = 'Heavy Rain / Heavy Shower' THEN avg_arrival_delay_sec END) -
        MAX(CASE WHEN weather_condition_group = 'Clear / Good Weather' THEN avg_arrival_delay_sec END), 
        2
    ) AS heavy_rain_delay_penalty_sec,

    -- DISRUPTION RATE (%): Compares non-punctual arrival percentages between clear and heavy rain conditions.
    MAX(CASE WHEN weather_condition_group = 'Clear / Good Weather' 
             THEN disruption_rate_pct END) AS disruption_pct_clear,
    MAX(CASE WHEN weather_condition_group = 'Heavy Rain / Heavy Shower' 
             THEN disruption_rate_pct END) AS disruption_pct_heavy_rain,

    -- Total stop pings recorded during heavy rain.
    MAX(CASE WHEN weather_condition_group = 'Heavy Rain / Heavy Shower' 
             THEN total_stop_observations END) AS obs_heavy_rain

FROM line_weather_performance

GROUP BY bus_line

-- Exclude any bus line that lacks clear weather observations.
HAVING MAX(CASE WHEN weather_condition_group = 'Clear / Good Weather' THEN avg_arrival_delay_sec END) IS NOT NULL
-- Order bus lines by the highest heavy rain delay penalty.
-- NULLS LAST places lines without heavy rain data at the bottom.
ORDER BY heavy_rain_delay_penalty_sec DESC NULLS LAST;

-- =====================================================================
-- Q2: Which bus lines are most frequently delayed? Between which stops are the delays greatest?
-- =====================================================================
-- PART 1: Top most frequently delayed bus lines
--   - Only include trips where live bus GPS tracking was active, filtering out static timetable estimates (static means when is_realtime = FALSE)
--   - Join fact_bus_performance with dim_route on route_key.
--   - Group by the route's short_name (line number) to combine both directions (e.g., inbound and outbound runs for Line 3) into a single line metric.
-- ---------------------------------------------------------------------
SELECT
-- Select bus lines by their short name
    r.short_name AS bus_line,

-- Total count of real-time stop arrivals observed for this line
    COUNT(*) AS total_stop_pings,

-- AVERAGE DELAY: Mean arrival delay in seconds across all pings for the line
    ROUND(AVG(f.arrival_delay_sec), 2) AS avg_delay_sec,

-- OVERALL NON-PUNCTUAL DISRUPTION RATE (%): Percentage of non-punctual arrivals (on_time_flag = FALSE), i.e. capturing arrival both >3 min late and >3 min early.
    ROUND(100.0 * COUNT(*) FILTER (WHERE f.on_time_flag = FALSE) / COUNT(*), 2) AS total_disruption_pct,

-- Now specifically LATE ARRIVALS:
-- 1. LATE ARRIVAL COUNT (n): Count of arrivals where delay exceeds the threshold, i.e. > 3 minutes (> 180 seconds)
    COUNT(*) FILTER (WHERE f.arrival_delay_sec > 180) AS late_arrivals_count,

-- 2. LATE ARRIVAL FREQUENCY (%): Percentage of arrivals that were strictly late, i.e. > 3 minutes (180 seconds)
    ROUND(100.0 * COUNT(*) FILTER (WHERE f.arrival_delay_sec > 180) / COUNT(*), 2) AS late_arrival_pct,
  
-- Joining the fact table and dimension table by shared key 'route_key'  
FROM dwh.fact_bus_performance f
JOIN dwh.dim_route r 
  ON f.route_key = r.route_key

-- Filter out static schedule rows (is_realtime = FALSE) which default delay to 0.
WHERE f.is_realtime = TRUE
GROUP BY r.short_name
-- Exclude low-frequency lines with fewer than 100 observations.
HAVING COUNT(*) >= 100
-- Ordering by delay frequency (highest % first), secondary by average magnitude
ORDER BY late_arrival_pct DESC, avg_delay_sec DESC;

-- ---------------------------------------------------------------------
-- PART 2: Greatest delays between consecutive stop segments
-- ---------------------------------------------------------------------
-- 1. Use the LAG() window function partitioned by (date_key, trip_key) and ordered by stop_index to compare every stop with its immediate predecessor.
WITH stop_delays_with_prev AS (
    SELECT
        f.performance_key,
        r.short_name AS bus_line,
        f.date_key,
        f.trip_key,
        f.stop_index,
        s.stop_name AS current_stop_name,
        s.district AS current_district,
        f.arrival_delay_sec AS current_delay_sec,
        
        -- Retrieve the previous stop's name within the same specific trip run
        LAG(s.stop_name) OVER w AS prev_stop_name,
        
        -- Retrieve the previous stop's delay value to compute incremental delay
        LAG(f.arrival_delay_sec) OVER w AS prev_delay_sec

    FROM dwh.fact_bus_performance f
    JOIN dwh.dim_route r ON f.route_key = r.route_key
    JOIN dwh.dim_stop s  ON f.stop_key  = s.stop_key
    
    WHERE f.is_realtime = TRUE
    
    WINDOW w AS (
        -- Isolates an individual bus run on a single date.
        PARTITION BY f.date_key, f.trip_key 
        -- Ensures sequential traversal along the trip path.
        ORDER BY f.stop_index
    )
),
-- 2. Compute the difference (delta) in arrival delay between consecutive stops: (Arrival Delay at Stop N) - (Arrival Delay at Stop N-1)
segment_delays AS (
    SELECT
        bus_line,
        prev_stop_name AS from_stop,
        current_stop_name AS to_stop,
        
        -- Count of unique trip runs observed traversing this specific segment
        COUNT(*) AS segment_trips_count,
        
        -- DELAY ACCUMULATED BETWEEN STOPS:
        -- > 0 = bus lost time between Stop N-1 and Stop N.
        -- < 0 = bus made up time between Stop N-1 and Stop N.
        ROUND(AVG(current_delay_sec - prev_delay_sec), 2) AS avg_delay_added_sec,
        
        -- Baseline: Average total delay recorded upon arrival at Stop N
        ROUND(AVG(current_delay_sec), 2) AS avg_arrival_delay_at_destination_sec

    FROM stop_delays_with_prev
    
    -- Filter out the first stop of a trip (prev_stop_name IS NULL)
    WHERE prev_stop_name IS NOT NULL
    
    GROUP BY 
        bus_line, 
        prev_stop_name, 
        current_stop_name
        
    -- Filter out low-volume segments, i.e. < 30
    HAVING COUNT(*) >= 30
)
-- 3. Aggregate these deltas by stop pair (from_stop -> to_stop) per bus line.
SELECT
    bus_line,
    from_stop,
    to_stop,
    segment_trips_count,
    avg_delay_added_sec,
    avg_arrival_delay_at_destination_sec
FROM segment_delays

-- Order by the segments that introduce the greatest amount of delay
ORDER BY avg_delay_added_sec DESC;

-- =====================================================================
-- Q3: At what times of day are delays greatest? On which days are delays greatest?
-- =====================================================================
-- PART 1: Delays by hour of day
--   - time_key = SCHEDULED arrival minute, so we group by when the bus was supposed to arrive.
--   - Hour is the grouping level; time_of_day and is_peak_hour are attributes of the hour, shown as labels.
-- ---------------------------------------------------------------------
SELECT
    t.hour,
    t.time_of_day,
    t.is_peak_hour,

-- Total real-time stop arrivals observed in this hour
    COUNT(*) AS total_stop_observations,

-- AVERAGE DELAY: signed mean (early arrivals cancel out late ones)
    ROUND(AVG(f.arrival_delay_sec), 2) AS avg_arrival_delay_sec,

-- AVERAGE ABSOLUTE DEVIATION: how far from the timetable regardless of direction
    ROUND(AVG(ABS(f.arrival_delay_sec)), 2) AS avg_abs_deviation_sec,

-- LATE ARRIVAL FREQUENCY (%): arrivals > 3 min (180 s) late
    ROUND(100.0 * COUNT(*) FILTER (WHERE f.arrival_delay_sec > 180) / COUNT(*), 2) AS late_arrival_pct,

-- DISRUPTION RATE (%): arrivals outside the +/- 3 min buffer (on_time_flag = FALSE)
    ROUND(100.0 * COUNT(*) FILTER (WHERE f.on_time_flag = FALSE) / COUNT(*), 2) AS disruption_rate_pct

FROM dwh.fact_bus_performance f
JOIN dwh.dim_time t
  ON f.time_key = t.time_key

-- Only measured delays; cancelled trips have no meaningful arrival delay.
WHERE f.is_realtime = TRUE
  AND f.is_canceled = FALSE

GROUP BY t.hour, t.time_of_day, t.is_peak_hour
-- Exclude hours with too few observations (e.g. late night).
HAVING COUNT(*) >= 30
-- Hours with the greatest average delay first
ORDER BY avg_arrival_delay_sec DESC;

-- ---------------------------------------------------------------------
-- PART 2: Delays by day of week
--   - Public holidays are excluded: they run on a weekend timetable and would distort the weekday they fall on.
--   - days_observed shows how many distinct dates stand behind each weekday:
--     with only a few weeks of data, one bad (e.g. snowy) day can dominate a weekday average.
-- ---------------------------------------------------------------------
SELECT
    d.weekday_nr,
    d.weekday,
    d.is_weekend,

-- Number of distinct service dates contributing to this weekday
    COUNT(DISTINCT d.date_key) AS days_observed,
    COUNT(*) AS total_stop_observations,

    ROUND(AVG(f.arrival_delay_sec), 2) AS avg_arrival_delay_sec,
    ROUND(AVG(ABS(f.arrival_delay_sec)), 2) AS avg_abs_deviation_sec,
    ROUND(100.0 * COUNT(*) FILTER (WHERE f.arrival_delay_sec > 180) / COUNT(*), 2) AS late_arrival_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE f.on_time_flag = FALSE) / COUNT(*), 2) AS disruption_rate_pct

FROM dwh.fact_bus_performance f
JOIN dwh.dim_date d
  ON f.date_key = d.date_key

WHERE f.is_realtime = TRUE
  AND f.is_canceled = FALSE
  AND d.is_holiday = FALSE

GROUP BY d.weekday_nr, d.weekday, d.is_weekend
HAVING COUNT(*) >= 30
-- Weekdays with the greatest average delay first
ORDER BY avg_arrival_delay_sec DESC;

-- =====================================================================
-- Q4: Which districts (or areas around stops) experience the greatest schedule deviations due to bad weather?
-- =====================================================================
-- Approach: compare each district's deviation in BAD weather against its own CLEAR weather baseline.
--   - Bad weather = weather_category IN ('rain', 'snow', 'fog'); baseline = 'clear'; 'other' is excluded.
--   - Deviation = AVG(ABS(arrival_delay_sec)): early and late both count as deviating from the schedule.
--   - District comes from dim_stop (SCD Type 2): the fact row's stop_key already points to the stop
--     version valid at event time, so no is_current filter is needed.
-- ---------------------------------------------------------------------
WITH stop_events_weather AS (
    SELECT
        s.district,
        CASE
            WHEN w.weather_category = 'clear'                  THEN 'clear'
            WHEN w.weather_category IN ('rain', 'snow', 'fog') THEN 'bad'
        END AS weather_group,
        f.arrival_delay_sec,
        f.on_time_flag
    FROM dwh.fact_bus_performance f
    JOIN dwh.dim_stop s
      ON f.stop_key = s.stop_key
    JOIN dwh.fact_weather w
      ON f.weather_key = w.weather_key
    WHERE f.is_realtime = TRUE
      AND f.is_canceled = FALSE
      AND s.district IS NOT NULL
),

-- ---------------------------------------------------------------------
-- Aggregate to one row per (district, weather_group).
-- ---------------------------------------------------------------------
district_weather AS (
    SELECT
        district,
        weather_group,
        COUNT(*) AS total_stop_observations,
        AVG(arrival_delay_sec) AS avg_arrival_delay_sec,
        AVG(ABS(arrival_delay_sec)) AS avg_abs_deviation_sec,
        100.0 * COUNT(*) FILTER (WHERE on_time_flag = FALSE) / COUNT(*) AS disruption_rate_pct
    FROM stop_events_weather
    -- Drops the 'other' weather category (weather_group is NULL)
    WHERE weather_group IS NOT NULL
    GROUP BY district, weather_group
    -- At least 30 observations per district and weather group
    HAVING COUNT(*) >= 30
)

-- ---------------------------------------------------------------------
-- Pivot to one row per district: clear baseline vs bad weather side by side.
-- ---------------------------------------------------------------------
SELECT
    district,

    MAX(total_stop_observations) FILTER (WHERE weather_group = 'clear') AS obs_clear,
    MAX(total_stop_observations) FILTER (WHERE weather_group = 'bad')   AS obs_bad_weather,

-- Average absolute schedule deviation (seconds)
    ROUND(MAX(avg_abs_deviation_sec) FILTER (WHERE weather_group = 'clear'), 2) AS abs_deviation_clear_sec,
    ROUND(MAX(avg_abs_deviation_sec) FILTER (WHERE weather_group = 'bad'),   2) AS abs_deviation_bad_sec,

-- "Bad weather penalty": extra deviation in bad weather over the district's own clear baseline
    ROUND(
        MAX(avg_abs_deviation_sec) FILTER (WHERE weather_group = 'bad') -
        MAX(avg_abs_deviation_sec) FILTER (WHERE weather_group = 'clear'),
        2
    ) AS bad_weather_penalty_sec,

-- Disruption rate (%) and its increase in percentage points
    ROUND(MAX(disruption_rate_pct) FILTER (WHERE weather_group = 'clear'), 2) AS disruption_pct_clear,
    ROUND(MAX(disruption_rate_pct) FILTER (WHERE weather_group = 'bad'),   2) AS disruption_pct_bad,
    ROUND(
        MAX(disruption_rate_pct) FILTER (WHERE weather_group = 'bad') -
        MAX(disruption_rate_pct) FILTER (WHERE weather_group = 'clear'),
        2
    ) AS disruption_increase_pp

FROM district_weather
GROUP BY district
-- Keep only districts that have BOTH a clear and a bad weather group (otherwise no comparison is possible)
HAVING COUNT(*) = 2
-- Districts where bad weather adds the most deviation first
ORDER BY bad_weather_penalty_sec DESC;

-- =====================================================================
-- Q5: To what extent do difficult road sections and weather conditions (e.g., snowfall or rain)
--     slow down traffic in a specific city district or between stops?
-- =====================================================================
-- Measure: avg_speed_kmh = mean GPS speed during the 120 s before the bus arrived at the stop,
--   i.e. the speed on the approach to that stop.
-- Slowdown (%) = 100 * (1 - speed in rain or snow / speed in clear weather).
-- ---------------------------------------------------------------------
-- PART 1: Speed by district and weather condition
--   To look at one specific district, add e.g.  AND s.district = 'Annelinn'  to the WHERE clause.
-- ---------------------------------------------------------------------
WITH district_speed AS (
    SELECT
        s.district,
        w.weather_category,
        COUNT(*) AS total_stop_observations,
        AVG(f.avg_speed_kmh) AS avg_speed_kmh
    FROM dwh.fact_bus_performance f
    JOIN dwh.dim_stop s
      ON f.stop_key = s.stop_key
    JOIN dwh.fact_weather w
      ON f.weather_key = w.weather_key
    WHERE f.is_realtime = TRUE
      AND f.is_canceled = FALSE
      -- Speed is only available when GPS pings were matched in the 120 s window
      AND f.avg_speed_kmh IS NOT NULL
      AND s.district IS NOT NULL
      AND w.weather_category IN ('clear', 'rain', 'snow')
    GROUP BY s.district, w.weather_category
    HAVING COUNT(*) >= 30
)
SELECT
    district,

    ROUND(MAX(avg_speed_kmh) FILTER (WHERE weather_category = 'clear'), 1) AS speed_clear_kmh,
    ROUND(MAX(avg_speed_kmh) FILTER (WHERE weather_category = 'rain'),  1) AS speed_rain_kmh,
    ROUND(MAX(avg_speed_kmh) FILTER (WHERE weather_category = 'snow'),  1) AS speed_snow_kmh,

-- Slowdown relative to the clear weather baseline (NULLIF avoids division by zero)
    ROUND(100.0 * (1 - MAX(avg_speed_kmh) FILTER (WHERE weather_category = 'rain')
                     / NULLIF(MAX(avg_speed_kmh) FILTER (WHERE weather_category = 'clear'), 0)), 1) AS rain_slowdown_pct,
    ROUND(100.0 * (1 - MAX(avg_speed_kmh) FILTER (WHERE weather_category = 'snow')
                     / NULLIF(MAX(avg_speed_kmh) FILTER (WHERE weather_category = 'clear'), 0)), 1) AS snow_slowdown_pct,

    MAX(total_stop_observations) FILTER (WHERE weather_category = 'rain') AS obs_rain,
    MAX(total_stop_observations) FILTER (WHERE weather_category = 'snow') AS obs_snow

FROM district_speed
GROUP BY district
-- A clear weather baseline is required for the comparison
HAVING MAX(avg_speed_kmh) FILTER (WHERE weather_category = 'clear') IS NOT NULL
ORDER BY snow_slowdown_pct DESC NULLS LAST, rain_slowdown_pct DESC NULLS LAST;

-- ---------------------------------------------------------------------
-- PART 2: Difficult road sections between consecutive stops, by weather
--   - A road section is a physical stop pair (from_stop -> to_stop), so we aggregate ACROSS bus lines
--     (unlike Q2, which looks per line).
--   - Stops are identified by stop_id, not stop_name: two stops on opposite sides of a road share a name.
--   - LAG() runs over ALL rows of the trip (no is_realtime filter before the window), and we then require
--     stop_index = prev_stop_index + 1, so a missing or non-realtime stop never creates a fake "segment".
--   - "Difficult" = low speed in clear weather (speed_clear_kmh) and/or a large weather slowdown.
-- ---------------------------------------------------------------------
WITH stop_sequence AS (
    SELECT
        f.stop_index,
        f.is_realtime,
        f.is_canceled,
        f.arrival_delay_sec,
        f.avg_speed_kmh,
        f.weather_key,
        s.stop_id,
        s.stop_name,
        s.district,

        LAG(f.stop_index)        OVER w AS prev_stop_index,
        LAG(f.is_realtime)       OVER w AS prev_is_realtime,
        LAG(s.stop_id)           OVER w AS prev_stop_id,
        LAG(s.stop_name)         OVER w AS prev_stop_name,
        LAG(f.arrival_delay_sec) OVER w AS prev_delay_sec

    FROM dwh.fact_bus_performance f
    JOIN dwh.dim_stop s
      ON f.stop_key = s.stop_key

    WINDOW w AS (
        -- One bus run on one service date, traversed in stop order
        PARTITION BY f.date_key, f.trip_key
        ORDER BY f.stop_index
    )
),

-- ---------------------------------------------------------------------
-- One row per traversal of a segment, tagged with the weather at arrival.
-- ---------------------------------------------------------------------
segments AS (
    SELECT
        ss.prev_stop_id,
        ss.stop_id,
        ss.prev_stop_name AS from_stop,
        ss.stop_name      AS to_stop,
        -- Segment is assigned to the district of its destination stop
        ss.district,
        w.weather_category,
        ss.avg_speed_kmh,
        -- Delay accumulated on this segment (> 0 = bus lost time)
        ss.arrival_delay_sec - ss.prev_delay_sec AS delay_added_sec
    FROM stop_sequence ss
    JOIN dwh.fact_weather w
      ON ss.weather_key = w.weather_key
    WHERE ss.is_realtime = TRUE
      AND ss.prev_is_realtime = TRUE
      AND ss.is_canceled = FALSE
      -- Only truly consecutive stops
      AND ss.stop_index = ss.prev_stop_index + 1
      AND ss.avg_speed_kmh IS NOT NULL
      AND w.weather_category IN ('clear', 'rain', 'snow')
),

segment_weather AS (
    SELECT
        prev_stop_id,
        stop_id,
        from_stop,
        to_stop,
        district,
        weather_category,
        COUNT(*) AS segment_trips_count,
        AVG(avg_speed_kmh)   AS avg_speed_kmh,
        AVG(delay_added_sec) AS avg_delay_added_sec
    FROM segments
    GROUP BY prev_stop_id, stop_id, from_stop, to_stop, district, weather_category
    HAVING COUNT(*) >= 30
)

-- ---------------------------------------------------------------------
-- Pivot to one row per road section.
-- ---------------------------------------------------------------------
SELECT
    from_stop,
    to_stop,
    district,

    ROUND(MAX(avg_speed_kmh) FILTER (WHERE weather_category = 'clear'), 1) AS speed_clear_kmh,
    ROUND(MAX(avg_speed_kmh) FILTER (WHERE weather_category = 'rain'),  1) AS speed_rain_kmh,
    ROUND(MAX(avg_speed_kmh) FILTER (WHERE weather_category = 'snow'),  1) AS speed_snow_kmh,

    ROUND(100.0 * (1 - MAX(avg_speed_kmh) FILTER (WHERE weather_category = 'rain')
                     / NULLIF(MAX(avg_speed_kmh) FILTER (WHERE weather_category = 'clear'), 0)), 1) AS rain_slowdown_pct,
    ROUND(100.0 * (1 - MAX(avg_speed_kmh) FILTER (WHERE weather_category = 'snow')
                     / NULLIF(MAX(avg_speed_kmh) FILTER (WHERE weather_category = 'clear'), 0)), 1) AS snow_slowdown_pct,

-- Delay added on the segment (seconds) in clear vs bad weather
    ROUND(MAX(avg_delay_added_sec) FILTER (WHERE weather_category = 'clear'), 1) AS delay_added_clear_sec,
    ROUND(MAX(avg_delay_added_sec) FILTER (WHERE weather_category = 'rain'),  1) AS delay_added_rain_sec,
    ROUND(MAX(avg_delay_added_sec) FILTER (WHERE weather_category = 'snow'),  1) AS delay_added_snow_sec,

    MAX(segment_trips_count) FILTER (WHERE weather_category = 'clear') AS obs_clear

FROM segment_weather
GROUP BY prev_stop_id, stop_id, from_stop, to_stop, district
HAVING MAX(avg_speed_kmh) FILTER (WHERE weather_category = 'clear') IS NOT NULL
-- Sections that slow down the most in snow or rain first
ORDER BY GREATEST(
             100.0 * (1 - MAX(avg_speed_kmh) FILTER (WHERE weather_category = 'snow')
                        / NULLIF(MAX(avg_speed_kmh) FILTER (WHERE weather_category = 'clear'), 0)),
             100.0 * (1 - MAX(avg_speed_kmh) FILTER (WHERE weather_category = 'rain')
                        / NULLIF(MAX(avg_speed_kmh) FILTER (WHERE weather_category = 'clear'), 0))
         ) DESC NULLS LAST;
