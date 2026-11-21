-- Type 2 historical dimension from snapshot. The FIRST version begins at
-- 1900-01-01, allowing historical facts from before the first snapshot to join.
-- District: the stops API has none, so each stop version is assigned to the nearest
-- Tartu district centre (seed tartu_district_centres). It is derived here from the
-- version's own coordinates, not in silver, so all versions (including history) get one.
{{ config(materialized='table', schema='gold') }}

-- Stops further than this from every district centre are outside Tartu (suburban lines).
{% set max_district_distance_km = 2.5 %}

with stop_versions as (
    select
        stop_id::text as stop_id,
        stop_code::text as stop_code,
        stop_name::text as stop_name,
        latitude::numeric(9,6) as latitude,
        longitude::numeric(9,6) as longitude,
        dbt_valid_from,
        dbt_valid_to,
        row_number() over (partition by stop_id order by dbt_valid_from) as version_nr
    from {{ ref('snap_stops') }}
)
select
    md5(stop_id || '|' || dbt_valid_from::text) as stop_key,
    stop_id, stop_code, stop_name, latitude, longitude,
    case
        when nearest.distance_km <= {{ max_district_distance_km }} then nearest.district
        else 'Outside Tartu'
    end::text as district,
    case when version_nr = 1
        then '1900-01-01 00:00:00+00'::timestamptz
        else dbt_valid_from
    end as valid_from,
    coalesce(dbt_valid_to, '9999-12-31 00:00:00+00'::timestamptz) as valid_to,
    (dbt_valid_to is null) as is_current
from stop_versions
-- Nearest district centre. Equirectangular distance: 1 degree latitude = 111.32 km,
-- longitude shrinks by cos(58.38 deg) = 0.5243 at Tartu's latitude. Accurate enough at city scale.
left join lateral (
    select
        c.district,
        111.32 * sqrt(
            power(stop_versions.latitude - c.latitude, 2)
            + power((stop_versions.longitude - c.longitude) * 0.5243, 2)
        ) as distance_km
    from {{ ref('tartu_district_centres') }} c
    order by distance_km
    limit 1
) nearest on true
