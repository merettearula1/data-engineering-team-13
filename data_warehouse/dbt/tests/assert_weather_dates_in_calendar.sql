select w.weather_key
from {{ ref('fact_weather') }} w
left join {{ ref('dim_date') }} d on w.date_key = d.date_key
where d.date_key is null
