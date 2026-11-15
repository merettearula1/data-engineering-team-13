-- Type 2 historical dimension from snapshot. The FIRST version begins at
-- 1900-01-01, allowing historical facts from before the first snapshot to join.
{{ config(materialized='table', schema='gold') }}

with stop_versions as (
    select
        stop_id::text as stop_id,
        stop_code::text as stop_code,
        stop_name::text as stop_name,
        latitude::numeric(9,6) as latitude,
        longitude::numeric(9,6) as longitude,
        district::text as district,
        dbt_valid_from,
        dbt_valid_to,
        row_number() over (partition by stop_id order by dbt_valid_from) as version_nr
    from {{ ref('snap_stops') }}
)
select
    md5(stop_id || '|' || dbt_valid_from::text) as stop_key,
    stop_id, stop_code, stop_name, latitude, longitude, district,
    case when version_nr = 1
        then '1900-01-01 00:00:00+00'::timestamptz
        else dbt_valid_from
    end as valid_from,
    coalesce(dbt_valid_to, '9999-12-31 00:00:00+00'::timestamptz) as valid_to,
    (dbt_valid_to is null) as is_current
from stop_versions
