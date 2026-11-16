-- Run after the full Silver -> snapshot -> Gold pipeline succeeds.
-- Confirm Bronze contains the seven expected source types:
select source_name, count(*) as n_rows, min(loaded_at) as first_loaded, max(loaded_at) as last_loaded
from bronze.raw_events group by source_name order by source_name;

-- Inspect the wrappers before your colleague finalizes Silver:
select source_name, jsonb_typeof(payload) as payload_type,
       left(payload::text, 400) as sample_json
from bronze.raw_events
where source_name in ('bus_trip_stop_times','bus_trips','bus_live','weather','bus_routes','bus_stops')
order by id desc limit 12;

-- Expected: 730 days with the default calendar period, and 1440 times
select count(*) as date_count from gold.dim_date;
select count(*) as time_count from gold.dim_time;

-- Facts and join completeness:
select count(*) as n_rows,
       count(*) filter (where route_key is null) as missing_routes,
       count(*) filter (where stop_key is null) as missing_stops,
       count(*) filter (where weather_key is null) as no_weather_nearby,
       count(*) filter (where avg_speed_kmh is not null) as with_matched_speed
from gold.fact_bus_performance;
select count(*) as weather_observations from gold.fact_weather;

-- On-time KPI ONLY for realtime predictions (avoid schedule-only placeholder zeros).
select round(100.0 * avg(case when on_time_flag then 1.0 else 0.0 end), 1)
       as predicted_on_time_percent
from gold.fact_bus_performance where on_time_flag is not null and is_canceled = false;

-- Distinctness check: must return no rows.
select date_key, trip_key, stop_index, count(*)
from gold.fact_bus_performance
group by 1,2,3 having count(*) > 1;
