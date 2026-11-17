-- Grain: one station_name + one observed_at timestamp.
-- Silver is responsible for canonicalizing duplicate readings and preserving
-- the *source* observation time (not blindly the fetch/poll time).
{{ config(materialized='table', schema='gold') }}

-- One source observation per station and timestamp is required by the Silver contract.
-- If duplicate rows reach Gold, the dbt unique test should detect them,
-- rather than hiding conflicting readings with an arbitrary row_number().
with weather as (
    select * from {{ ref('silver_weather') }}
    where station_name is not null and observed_at is not null
)
select
    md5(station_name::text || '|' || observed_at::text) as weather_key,
    to_char(observed_at at time zone 'Europe/Tallinn', 'YYYYMMDD')::integer as date_key,
    (extract(hour from observed_at at time zone 'Europe/Tallinn')::integer * 100
     + extract(minute from observed_at at time zone 'Europe/Tallinn')::integer) as time_key,
    station_name::text as station_name,
    observed_at::timestamptz as observed_at,
    precipitation_mm::numeric as precipitation_mm,
    visibility_km::numeric as visibility_km,
    temperature_c::numeric as temperature_c,
    wind_speed_ms::numeric as wind_speed_ms,
    wind_speed_max_ms::numeric as wind_speed_max_ms,
    coalesce(weather_category::text, 'other') as weather_category
from weather
