-- Grain: one (service_date, trip_id, stop_index). A repeating stop_id is legal.
-- Delay represents an API real-time estimate, not independently verified actual arrival.
-- route_id MUST be enriched by Silver from bus_trips / bus_departures;
-- bus_trip_stop_times alone does not supply route_id.
{{ config(materialized='table', schema='gold') }}

with ranked_events as (
    select
        e.*,
        row_number() over (
            partition by e.service_date, e.trip_id, e.stop_index
            order by coalesce(e.is_realtime, false) desc,
                     e.observation_time desc nulls last
        ) as rn
    from {{ ref('silver_stop_events') }} e
    where e.service_date is not null
      and e.trip_id is not null
      and e.stop_index is not null
), events as (
    select * from ranked_events where rn = 1
), prepared as (
    select
        e.*,
        coalesce(e.is_realtime, false) as has_realtime,
        coalesce(e.is_canceled, false) as canceled,
        coalesce(e.realtime_arrival, e.scheduled_arrival,
                 e.observation_time) as event_time
    from events e
)
select
    md5(to_char(e.service_date, 'YYYYMMDD') || '|' || e.trip_id::text || '|' || e.stop_index::text)
        as performance_key,
    to_char(e.service_date, 'YYYYMMDD')::integer as date_key,
    -- Time dimension uses the SCHEDULED arrival minute (Europe/Tallinn).
    (extract(hour from e.scheduled_arrival at time zone 'Europe/Tallinn')::integer * 100
     + extract(minute from e.scheduled_arrival at time zone 'Europe/Tallinn')::integer)
        as time_key,
    dr.route_key,
    dt.trip_key,
    ds.stop_key,
    w.weather_key,
    e.scheduled_arrival::timestamptz as scheduled_arrival,
    e.scheduled_departure::timestamptz as scheduled_departure,
    case when e.has_realtime then e.realtime_arrival::timestamptz end as realtime_arrival,
    case when e.has_realtime then e.realtime_departure::timestamptz end as realtime_departure,
    case when e.has_realtime then e.arrival_delay_sec::integer end as arrival_delay_sec,
    case when e.has_realtime then e.departure_delay_sec::integer end as departure_delay_sec,
    case
        when e.has_realtime and e.arrival_delay_sec is not null
        then abs(e.arrival_delay_sec) <= 180
    end as on_time_flag,
    e.has_realtime as is_realtime,
    e.observation_time::timestamptz as observation_time,
    gps.avg_speed_kmh,
    gps.gps_ping_count,
    e.canceled as is_canceled,
    e.stop_index::integer as stop_index
from prepared e
left join {{ ref('dim_route') }} dr on dr.route_id = e.route_id
left join {{ ref('dim_trip') }} dt on dt.trip_id = e.trip_id
left join {{ ref('dim_stop') }} ds
    on ds.stop_id = e.stop_id
   and e.event_time >= ds.valid_from
   and e.event_time < ds.valid_to
-- Nearest observation at Tartu-Tõravere, no more than one hour away.
left join lateral (
    select fw.weather_key
    from {{ ref('fact_weather') }} fw
    where fw.station_name = '{{ var("weather_station_name", "Tartu-Tõravere") }}'
      and e.event_time is not null
      and fw.observed_at between e.event_time - interval '60 minutes'
                             and e.event_time + interval '60 minutes'
    order by abs(extract(epoch from (fw.observed_at - e.event_time))),
             fw.observed_at desc
    limit 1
) w on true
-- Mean GPS speed over the 120 seconds approaching predicted realtime arrival.
left join lateral (
    select
        round(avg(l.speed_kmh)::numeric, 2) as avg_speed_kmh,
        count(*)::integer as gps_ping_count
    from {{ ref('silver_live_positions') }} l
    where e.has_realtime
      and e.realtime_arrival is not null
      and l.trip_id = e.trip_id
      and l.service_date = e.service_date
      and l.update_time > e.realtime_arrival - interval '120 seconds'
      and l.update_time <= e.realtime_arrival
      and l.speed_kmh is not null
) gps on true
