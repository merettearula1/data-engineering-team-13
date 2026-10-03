# Tartu Bus Data API Overview

Bus movement and schedule data is queried from [tartu.pilet.ee] (https://tartu.pilet.ee/et/explore?selectedTab=routes).

## 1. Bus Stops Dataset (source for `/v1/stops`)

| Column | Description | Data Type | Sample Value |
| :--- | :--- | :--- | :--- |
| `id` | Unique stop identifier in the API | String | `"1:3111:0"` |
| `code` | Official national/local stop code | String | `"7820345-1"` |
| `name` | Stop name | String | `"Eha"` |
| `lat` | Geographical latitude of the stop | Float | `58.37027` |
| `lon` | Geographical longitude of the stop | Float | `26.72756` |
| `locationType` | Location type according to GTFS standard (e.g., 0 = stop) | Integer | `0` |
| `interchangePriority` | Transfer priority (if specified) | Integer / Null | `null` |
| `desc` | Additional stop description or note | String / Null | `"null"` |


## 2. Bus Routes in Tartu (source for `/v1/routes`)

| Column | Description | Data Type | Sample Value |
| :--- | :--- | :--- | :--- |
| `id` | Unique route identifier in the API | String | `"1:1_1688_1_3"` |
| `shortName` | Route number or short name | String | `"1"` |
| `longName` | Extended route description (origin and destination) | String | `"FI - Nõlvaku"` |
| `mode` | Transport mode (e.g., BUS) | String | `"BUS"` |
| `icon.color` | Hex code for the route icon/theme color | String | `"DE2C42"` |
| `icon.textColor` | Hex code for the route text color | String | `"DE2C42"` |
| `icon.shape` | Icon shape design type (if specified) | String / Null | `null` |
| `designation` | Additional route designation or label | String / Null | `null` |

## 3. Upcoming Departures at a Specific Stop (source for `/v1/stops/{id}/stoptimes`)

### `pattern` and `routeDetails` Object Fields

| Column | Description | Data Type | Sample Value |
| :--- | :--- | :--- | :--- |
| `pattern.id` | Identifier for the specific route path (pattern) | String | `"1:7_0634_1_3:0:01"` |
| `pattern.desc` | Line label / description at the pattern level | String | `"7"` |
| `pattern.routeId` | Associated route ID | String | `"1:7_0634_1_3"` |
| `routeDetails.id` | Associated route ID in detailed view | String | `"1:7_0634_1_3"` |
| `routeDetails.agency` | Transit agency / operator organisation | String / Null | `null` |
| `routeDetails.shortName` | Line number / short name | String | `"7"` |
| `routeDetails.longName` | Full route description | String | `"Tõrvandi - Raeplats - Kõrveküla"` |
| `routeDetails.mode` | Transport mode | String | `"BUS"` |
| `routeDetails.type` | GTFS transport type (3 = bus) | Integer | `3` |
| `routeDetails.icon.color` | Route color hex code | String | `"DE2C42"` |
| `routeDetails.icon.textColor` | Text color hex code | String | `"DE2C42"` |
| `routeDetails.icon.shape` | Icon shape design | String / Null | `null` |
| `routeDetails.url` | Route URL | String / Null | `null` |
| `routeDetails.operatorCode` | Operator code | String / Null | `null` |
| `routeDetails.operatorName` | Operator name | String / Null | `null` |

### `times` Array Elements

| Column | Description | Data Type | Sample Value |
| :--- | :--- | :--- | :--- |
| `stopId` | Stop ID | String | `"1:3161:0"` |
| `stopIndex` | Sequence number of the stop along the trip route | Integer | `23` |
| `stopCount` | Total number of stops on the trip | Integer | `31` |
| `scheduledArrival` | Scheduled arrival timestamp (with timezone) | ISO Timestamp | `"2026-09-29T16:39:30+03:00"` |
| `scheduledDeparture` | Scheduled departure timestamp (with timezone) | ISO Timestamp | `"2026-09-29T16:39:30+03:00"` |
| `realtimeArrival` | Real-time / predicted arrival timestamp | ISO Timestamp | `"2026-09-29T16:38:57+03:00"` |
| `realtimeDeparture` | Real-time / predicted departure timestamp | ISO Timestamp | `"2026-09-29T16:39:30+03:00"` |
| `arrivalDelay` | Arrival delay in seconds (negative = early) | Integer | `-33` |
| `departureDelay` | Departure delay in seconds | Integer | `0` |
| `timepoint` | Flag indicating if the stop is a fixed timing point | Boolean | `true` |
| `serviceDay` | Unix timestamp (in seconds) for the start of the service day | Long / Integer | `1790629200` |
| `headsign` | Destination text displayed on the front of the bus | String | `"Tõrvandi - Raeplats - Kõrveküla"` |
| `tripId` | Unique identifier for the specific bus trip | String | `"1:7_Tõrvandi - Raeplats - Kõrveküla_A>B1...` |
| `stopPoint` | Specific platform / post coordinate (if used) | String / Null | `null` |
| `realtime` | Flag indicating if data originates from live GPS tracking | Boolean | `true` |
| `canceled` | Flag indicating whether the stop departure was canceled | Boolean | `false` |
| `pickupType` | Passenger pickup restrictions (GTFS standard) | Integer / Null | `null` |
| `dropOffType` | Passenger drop-off restrictions (GTFS standard) | Integer / Null | `null` |
| `tripDirection` | Direction indicator for the trip (e.g., 0 or 1) | Integer / Null | `null` |


## 4. Trip Stop Schedules (source for `/v1/trips/stoptimes?tripId={TRIP_ID}`)

| Column | Description | Data Type | Sample Value |
| :--- | :--- | :--- | :--- |
| `tripId` | Unique bus trip identifier | String | `"1:7_Tõrvandi - Raeplats - Kõrveküla_A>B1...` |
| `mode` | Transport mode (if specified) | String / Null | `null` |
| `stopId` | Stop ID | String | `"1:3187:0"` |
| `stopName` | Stop name | String | `"Tõrvandi"` |
| `stopPoint` | Specific platform / post coordinate | String / Null | `null` |
| `stopIndex` | Sequence number of the stop on this specific trip | Integer | `0` |
| `stopCount` | Total stop count for the entire trip | Integer | `31` |
| `scheduledArrival` | Scheduled local arrival timestamp | ISO Timestamp | `"2026-09-29T16:29:00+03:00"` |
| `scheduledDeparture` | Scheduled local departure timestamp | ISO Timestamp | `"2026-09-29T16:30:00+03:00"` |
| `realtimeArrival` | Predicted / actual arrival timestamp | ISO Timestamp | `"2026-09-29T16:29:00+03:00"` |
| `realtimeDeparture` | Predicted / actual departure timestamp | ISO Timestamp | `"2026-09-29T16:30:00+03:00"` |
| `arrivalDelay` | Arrival variance from schedule in seconds | Integer | `0` |
| `departureDelay` | Departure variance from schedule in seconds | Integer | `0` |
| `timepoint` | Whether this is a fixed timetable checkpoint stop | Boolean | `true` |
| `realtime` | Whether this row contains real-time (GPS) data vs timetable-only | Boolean | `false` |
| `headsign` | Destination text on the bus screen | String | `"Tõrvandi - Raeplats - Kõrveküla"` |
| `canceled` | Whether this stop was skipped / canceled on the trip | Boolean | `false` |
| `pickupType` | Pickup restrictions | Integer / Null | `null` |
| `dropOffType` | Drop-off restrictions | Integer / Null | `null` |
| `tripDirection` | Trip direction code | Integer / Null | `null` |


# Weather API Overview

Weather observations are retrieved from [ilmateenistus.ee](https://www.ilmateenistus.ee/teenused/ilmainfo/eesti-vaatlusandmed-xml/). The project uses observations from the **Tartu-Tõravere weather station**.

The data gets updated after every 10 or 60 minutes, depending on the measured parameter. There are total of 19 columns.

| Column | Description | Data Type | Sample value |
| :--- | :--- | :--- | :--- |
| `name` | Station name. | String | Virtsu |
| `wmocode` | Station WMO code. | Integer | 26128 |
| `longitude` | Station longitude coordinate. | Float | 23.51355555534363 |
| `latitude` | Station latitude coordinate. | Float | 58.572674999100215 |
| `phenomenon` | Weather phenomenon occurring at the station; if absent, cloud cover degree (if measured). If visibility is over 2 km, cloud data is provided in case of mist (if cloudiness is measured). Updated every 10 minutes. | String | Light snowfall |
| `visibility` | Visibility (km). Updated 10 minutes past every hour. | Float | 34.0 |
| `precipitations` | Precipitation (mm) during the last hour. Snow, sleet, hail, and similar precipitation amounts are also presented in millimeters of water equivalent (1 cm of snow ~ 1 mm of water). Updated 10 minutes past every hour. | Float | 0 |
| `airpressure` | Air pressure (hPa). Standard pressure is 1013.25 hPa. Updated 10 minutes past every hour. | Float | 1005.4 |
| `relativehumidity` | Relative humidity (%). Updated 10 minutes past every hour. | Integer | 57 |
| `airtemperature` | Air temperature (°C). Updated every 10 minutes for meteorological stations and 10 minutes past every hour for hydrometeorological stations. | Float | -3.6 |
| `winddirection` | Wind direction (°). Updated every 10 minutes. | Integer | 101 |
| `windspeed` | Average wind speed (m/s). Updated every 10 minutes. | Float | 3.2 |
| `windspeedmax` | Maximum wind speed / gusts (m/s). Updated every 10 minutes. | Float | 5.1 |
| `waterlevel` | Inland water level (cm) relative to Amsterdam Ordnance Datum (NAP). Updated 10 minutes past every hour. | Integer | -49 |
| `waterlevel_eh2000` | Sea water level (cm) relative to Amsterdam Ordnance Datum (EH2000/NAP). Updated 10 minutes past every hour. | Integer | -28 |
| `watertemperature` | Water temperature (°C). Updated 10 minutes past every hour. | Float | -0.2 |
| `uvindex` | UV index. Updated every 10 minutes. | Float | 3.2 |
| `sunshineduration` | Daily sunshine duration (minutes) on the query date (cumulative data). Updated every 10 minutes. | Integer | 63 |
| `globalradiation` | Global solar radiation, 1-hour average (W/m²). Updated 10 minutes past every hour. | Integer | 207 |
