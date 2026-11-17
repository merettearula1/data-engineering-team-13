-- Type 1 dimension; Silver must expose one current row per route_id.
{{ config(materialized='table', schema='gold') }}

select
    md5(route_id::text) as route_key,
    route_id::text as route_id,
    short_name::text as short_name,
    long_name::text as long_name,
    mode::text as mode
from {{ ref('silver_routes') }}
where route_id is not null
