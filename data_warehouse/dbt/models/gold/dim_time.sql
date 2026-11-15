-- Static minute-of-day dimension (1,440 rows).
{{ config(materialized='table', schema='gold') }}

with minutes as (
    select m, (m / 60)::integer as hour, (m % 60)::integer as minute
    from generate_series(0, 1439) as minutes(m)
)
select
    hour * 100 + minute as time_key,
    hour,
    minute,
    case
        when hour between 6 and 8 then 'morning_peak'
        when hour between 9 and 14 then 'daytime'
        when hour between 15 and 17 then 'evening_peak'
        when hour between 18 and 22 then 'evening'
        else 'night'
    end as time_of_day,
    (hour in (6, 7, 8, 15, 16, 17)) as is_peak_hour
from minutes
