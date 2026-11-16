select performance_key
from {{ ref('fact_bus_performance') }}
where is_realtime = false
  and (arrival_delay_sec is not null or departure_delay_sec is not null
       or on_time_flag is not null)
