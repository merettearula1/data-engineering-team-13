-- No row should disagree with the +/- 180 seconds rule for live predictions.
select performance_key
from {{ ref('fact_bus_performance') }}
where on_time_flag is distinct from
    (case when is_realtime and arrival_delay_sec is not null
          then abs(arrival_delay_sec) <= 180 end)
