-- Type 1 dimension. Uses latest known trip metadata from stop events.
{{ config(materialized='table', schema='gold') }}

with ranked as (
    select
        trip_id, service_id, trip_headsign,
        row_number() over (
            partition by trip_id
            order by observation_time desc nulls last,
                     service_date desc nulls last
        ) as rn
    from {{ ref('silver_stop_events') }}
    where trip_id is not null
)
select
    md5(trip_id::text) as trip_key,
    trip_id::text as trip_id,
    service_id::text as service_id,
    trip_headsign::text as trip_headsign
from ranked
where rn = 1
