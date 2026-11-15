-- dbt singular tests must return ZERO rows when the assertion holds.
select date_key, trip_key, stop_index, count(*) as n
from {{ ref('fact_bus_performance') }}
group by date_key, trip_key, stop_index
having count(*) > 1
