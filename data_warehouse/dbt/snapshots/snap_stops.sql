-- dbt snapshot supplies historical versions when a stop's attributes change.
-- IMPORTANT: run `dbt snapshot --select snap_stops` after Silver is refreshed.
{% snapshot snap_stops %}
{{ config(
    target_schema='history',
    unique_key='stop_id',
    strategy='check',
    check_cols=['stop_code','stop_name','latitude','longitude','district'],
    invalidate_hard_deletes=True
) }}
select
    stop_id, stop_code, stop_name, latitude, longitude, district
from {{ ref('silver_stops') }}
where stop_id is not null
{% endsnapshot %}
