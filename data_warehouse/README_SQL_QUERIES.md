# Tartu Transit Analytics — Database Quality & Business Question Queries

## Database Quality Checks
### 1. Ingestion Health Check
Audits _bronze.raw_events_ by summarizing row counts and load timestamps (_first_loaded_ / _last_loaded_) per upstream source to verify pipeline completeness, historical backfill coverage, and data freshness.
```sql
select source_name, count(*) as n_rows, min(loaded_at) as first_loaded, max(loaded_at) as last_loaded
from bronze.raw_events
group by source_name
order by source_name;
```
LISA PILT.

### 2. Payload Structure Inspection
Samples the latest raw JSON records across transit and weather feeds (_bus_live_, _weather_, _bus_stops_, etc.) to verify top-level JSON types (object vs. array) and preview key structures before downstream Silver-layer parsing.
```sql
select source_name, jsonb_typeof(payload) as payload_type,
	 left(payload::text, 400) as sample_json
from bronze.raw_events
where source_name in ('bus_trip_stop_times','bus_trips','bus_live','weather','bus_routes','bus_stops')
order by id desc
limit 12;
```

LISA PILT.

### 3. Silver Layer Row Count Audit
Aggregates record counts across all six transformed Silver tables (_silver_stops_, _silver_routes_, _silver_trips_, _silver_stop_events_, _silver_live_positions_, and _silver_weather_) in a single view to verify post-transformation completeness and catch empty models or accidental join/unnest row explosions.
```sql
select 'silver_stops' as model, count(*) from silver.silver_stops
union all select 'silver_routes', count(*) from silver.silver_routes
union all select 'silver_trips', count(*) from silver.silver_trips
union all select 'silver_stop_events', count(*) from silver.silver_stop_events
union all select 'silver_live_positions', count(*) from silver.silver_live_positions
union all select 'silver_weather', count(*) from silver.silver_weather;
```

LISA PILT.

### 4. SCD Type 2 Snapshot Audit (_history.snap_stops_)
Compares total historical versions, distinct stop_id entities, and active records (_dbt_valid_to is null_) to verify that dbt snapshot tracking captures historical changes without creating duplicate active rows.
```sql
select count(*) as versions,
        count(distinct stop_id) as stops,
        count(*) filter (where dbt_valid_to is null) as current_versions
 from history.snap_stops;
```

LISA PILT.

### 5. Date & Time Dimension Check
Verifies row counts in _gold.dim_date_ and _gold.dim_time_ to confirm complete calendar and time-of-day coverage (e.g., 1,440 minutes/day) before joining Gold-layer fact tables.
```sql
select
	(select count(*) from gold.dim_date) as date_count,
	(select count(*) from gold.dim_time) as time_count;
```

LISA PILT.

### 6. Fact Table Integrity & Enrichment Audit (_gold.fact_bus_performance_)
Evaluates total fact row volume alongside orphaned dimension foreign keys (_route_key_, _stop_key_) and enrichment match rates for nearby weather (_weather_key_) and live GPS speed telemetry (_avg_speed_kmh_).
```sql
select count(*) as n_rows,
	 count(*) filter (where route_key is null) as missing_routes,
	 count(*) filter (where stop_key is null) as missing_stops,
	 count(*) filter (where weather_key is null) as no_weather_nearby,
	 count(*) filter (where avg_speed_kmh is not null) as with_matched_speed
from gold.fact_bus_performance;
```
LISA PILT.

### 7. Weather Fact Volume Check (_gold.fact_weather_)
Confirms the total count of analytics-ready weather observations in the Gold layer to verify successful Silver-to-Gold loading and completeness.
```sql
select count(*) as weather_observations from gold.fact_weather;
```

LISA PILT.

### 8. On-Time Performance KPI Validation (_gold.fact_bus_performance_)
Calculates the overall percentage of on-time bus events across active, non-canceled trips with valid punctuality flags (_on_time_flag is not null_) to validate Gold-layer business metric accuracy.
```sql
select round(100.0 * avg(case when on_time_flag then 1.0 else 0.0 end), 1) as predicted_on_time_percent
from gold.fact_bus_performance
where on_time_flag is not null and is_canceled = false;
```

LISA PILT.

### 9. Fact Table Grain & Uniqueness Test (_gold.fact_bus_performance_)
Groups records by (_date_key_, _trip_key_, _stop_index_) and filters for _count(*) > 1_ to guarantee primary key uniqueness at the stop-event grain and detect duplicate loads or fan-out joins (expects 0 rows).
```sql
select date_key, trip_key, stop_index, count(*)
from gold.fact_bus_performance
group by 1, 2, 3
having count(*) > 1;
```

LISA PILT.

## Business Question Outputs
The Demo SQL Queries: [Demo_queries.sql](https://github.com/merettearula1/data-engineering-team-13/blob/main/datasets_architecture/modeling/Demo_queries.sql)
### Q1
**On which bus lines is the average delay (in seconds) greatest during adverse weather conditions (weather phenomena) or heavy rainfall compared to clear weather?**
As there were not enough data collected yet, the output for _rain_ vs. _clear_ was empty.
```sql
SELECT r.short_name AS bus_line,
	 w.weather_category,
	 COUNT(*) AS observations,
	 ROUND(AVG(f.arrival_delay_sec), 2) AS avg_delay_sec,
	 ROUND(100.0 * COUNT(*) FILTER (WHERE f.on_time_flag = FALSE) / COUNT(*), 2) AS disruption_pct
FROM gold.fact_bus_performance f
JOIN gold.dim_route r    ON f.route_key = r.route_key
JOIN gold.fact_weather w ON f.weather_key = w.weather_key
WHERE f.is_realtime = TRUE
GROUP BY r.short_name, w.weather_category
HAVING COUNT(*) >= 30
ORDER BY r.short_name, w.weather_category;
```
LISA PILT. 
To check if the query works, we instead checked _rain_ vs. _other_:
```sql
WITH weather_phenomena_classified AS (
      SELECT weather_key,
          CASE
              WHEN weather_category IN ('rain', 'snow', 'fog') THEN 'Adverse Weather (Rain/Snow/Fog)'
              WHEN weather_category = 'other'                  THEN 'Overcast / Other'
          END AS weather_condition_group
      FROM gold.fact_weather
  ),
  line_weather_performance AS (
      SELECT r.short_name AS bus_line,
             w.weather_condition_group,
             COUNT(*) AS total_stop_observations,
             ROUND(AVG(f.arrival_delay_sec), 2) AS avg_arrival_delay_sec,
             ROUND(100.0 * COUNT(*) FILTER (WHERE f.on_time_flag = FALSE) / COUNT(*), 2) AS disruption_rate_pct
      FROM gold.fact_bus_performance f
      JOIN gold.dim_route r ON f.route_key = r.route_key
      JOIN weather_phenomena_classified w ON f.weather_key = w.weather_key
      WHERE f.is_realtime = TRUE
        AND w.weather_condition_group IS NOT NULL
      GROUP BY r.short_name, w.weather_condition_group
      HAVING COUNT(*) >= 30
  )
  SELECT bus_line,
      MAX(CASE WHEN weather_condition_group = 'Overcast / Other'                THEN avg_arrival_delay_sec END) AS avg_delay_baseline_sec,
      MAX(CASE WHEN weather_condition_group = 'Adverse Weather (Rain/Snow/Fog)' THEN avg_arrival_delay_sec END) AS avg_delay_adverse_sec,
      ROUND(MAX(CASE WHEN weather_condition_group = 'Adverse Weather (Rain/Snow/Fog)' THEN avg_arrival_delay_sec END) -
            MAX(CASE WHEN weather_condition_group = 'Overcast / Other'                THEN avg_arrival_delay_sec END), 2) AS
  adverse_delay_penalty_sec,
      MAX(CASE WHEN weather_condition_group = 'Overcast / Other'                THEN disruption_rate_pct END) AS disruption_pct_baseline,
      MAX(CASE WHEN weather_condition_group = 'Adverse Weather (Rain/Snow/Fog)' THEN disruption_rate_pct END) AS disruption_pct_adverse,
      MAX(CASE WHEN weather_condition_group = 'Overcast / Other'                THEN total_stop_observations END) AS obs_baseline,
      MAX(CASE WHEN weather_condition_group = 'Adverse Weather (Rain/Snow/Fog)' THEN total_stop_observations END) AS obs_adverse
  FROM line_weather_performance
  GROUP BY bus_line
  HAVING MAX(CASE WHEN weather_condition_group = 'Overcast / Other' THEN avg_arrival_delay_sec END) IS NOT NULL
  ORDER BY adverse_delay_penalty_sec DESC NULLS LAST;
```

LISA PILT.

### Q2
**Which bus lines are most frequently delayed?**
LISA PILT

**Between which stops are the delays greatest**
Compared to the inital query, to display the results with such few datapoints, we changed the _HAVING COUNT(*)_ from 30 to 3. In the inital query, it is still 30.
LISA PILT

### Q3
**At what times of day are delays greatest?**

**On which days are delays greatest?***

LISA PILT.

### Q4
**Which districts (or areas around stops) experience the greatest schedule deviations due to bad weather?**

LISA PILT

### Q5
**To what extent do difficult road sections and weather conditions (e.g., snowfall or rain) slow down traffic in a specific city district?**

LISA PILT.

**Or between stops?**
Again. Compared to the inital query, to display the results with such few datapoints, we changed the _HAVING COUNT(*)_ from 30 to 3. In the inital query, it is still 30.

LISA PILT.

