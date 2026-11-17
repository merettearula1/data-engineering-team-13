-- Silver: weather observations
-- bronze.raw_events (JSONB) -> one row per station x observation time
-- Materialised as a view (dbt_project.yml), like the week 03 intermediate models.

WITH polls AS (
    SELECT
        id                                                     AS bronze_id,
        payload->>'name'                                       AS station_name,
        COALESCE(
            to_timestamp((payload->>'source_observation_time')::bigint),
            (payload->>'fetched_at')::timestamptz
        )                                                      AS observed_at,
        (payload->>'precipitations')::numeric                  AS precipitation_mm,
        (payload->>'visibility')::numeric                      AS visibility_km,
        (payload->>'airtemperature')::numeric                  AS temperature_c,
        (payload->>'windspeed')::numeric                       AS wind_speed_ms,
        (payload->>'windspeedmax')::numeric                    AS wind_speed_max_ms,
        payload->>'phenomenon'                                 AS phenomenon
    FROM {{ source('bronze', 'raw_events') }}
    WHERE source_name = 'weather'
),

ranked AS (
    -- a reloaded file repeats the same poll: number the copies, newest load first
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY station_name, observed_at
            ORDER BY bronze_id DESC
        ) AS copy_nr
    FROM polls
    WHERE station_name IS NOT NULL
      AND observed_at IS NOT NULL
)

SELECT
    station_name,
    observed_at,
    precipitation_mm,
    visibility_km,
    temperature_c,
    wind_speed_ms,
    wind_speed_max_ms,
    CASE
        WHEN phenomenon IN ('Clear', 'Few clouds', 'Variable clouds')
            THEN 'clear'
        WHEN phenomenon IN ('Light rain', 'Moderate rain', 'Heavy rain',
                            'Light shower', 'Moderate shower', 'Heavy shower')
            THEN 'rain'
        WHEN phenomenon IN ('Light snowfall', 'Moderate snowfall', 'Heavy snowfall',
                            'Light snow shower', 'Moderate snow shower', 'Heavy snow shower')
            THEN 'snow'
        WHEN phenomenon IN ('Fog')
            THEN 'fog'
        -- UNCATEGORIZED FOR NOW: Light/Moderate sleet, Hail, Glaze, Mist are 'other' for now
        ELSE 'other'                     -- also overcast, unknown and NULL
    END                                                        AS weather_category,
    phenomenon
FROM ranked
WHERE copy_nr = 1