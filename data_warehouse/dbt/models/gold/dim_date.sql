-- Static calendar dimension: dates from the period planned in Project 1.
{{ config(materialized='table', schema='gold') }}

with calendar as (
    select day::date as full_date
    from generate_series(
        '{{ var("calendar_start", "2026-01-01") }}'::date,
        '{{ var("calendar_end", "2027-12-31") }}'::date,
        interval '1 day'
    ) as dates(day)
)
select
    to_char(full_date, 'YYYYMMDD')::integer as date_key,
    full_date,
    extract(year from full_date)::integer as year,
    extract(month from full_date)::integer as month,
    trim(to_char(full_date, 'Day')) as weekday,
    extract(isodow from full_date)::integer as weekday_nr,
    (extract(isodow from full_date) in (6, 7)) as is_weekend,
    (to_char(full_date, 'MM-DD') in
        ('01-01','02-24','05-01','06-23','06-24','08-20','12-24','12-25','12-26')) as is_holiday
from calendar
-- NOTE: movable holidays are not covered (same limitation as Project 1).
