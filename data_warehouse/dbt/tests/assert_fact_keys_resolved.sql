-- Missing dimension keys indicate a Silver contract/enrichment problem.
select performance_key
from {{ ref('fact_bus_performance') }}
where route_key is null or trip_key is null or stop_key is null or time_key is null
