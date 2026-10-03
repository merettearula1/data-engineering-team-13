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
