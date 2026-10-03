# Tartu Transit Analytics using live bus data and live weather data

In the repository, there are following files:
* Python-scripts for accessing [live bus data](https://github.com/merettearula1/data-engineering-team-13/blob/main/bus_live_data.py) and live weather data ([SIIA ON PYTHONI KOODI VAJA]())
* [Description of the both datasets: live bus data and live weather data](https://github.com/merettearula1/data-engineering-team-13/blob/main/Datasets.md)
* Sample data snapshots of [raw live bus data](https://github.com/merettearula1/data-engineering-team-13/blob/main/sample_bus_data_snapshot.json) and raw live weather data [SIIA ON SNAPSHOTI VAJA]().
* [Data Dictionary](https://github.com/merettearula1/data-engineering-team-13/blob/main/Data_dictionary.md) of the star schema
* [SQL Demo Queries](https://github.com/merettearula1/data-engineering-team-13/blob/main/Demo_queries.md) based on the project's Business Questions

## Data Sources
The full descriptions of the datasets can be found [here](https://github.com/merettearula1/data-engineering-team-13/blob/main/Datasets.md).

### How the live bus data is structured in the model?
Bus movement and schedule data is queried from [tartu.pilet.ee](https://tartu.pilet.ee/et/explore?selectedTab=routes) and is used to describe:

* Bus locations and movements (`Bus-live-data`, 14 columns)
* Bus stops (`Bus-stops`, 5 columns)
* Routes (`Bus-routes`, 3 columns)
* Scheduled trips (`Bus-route-trips`, 5 columns)
* Scheduled times (`Bus-schedule`, 16 columns)

![img](bus_data_sources_diagram.png)

## Data Dictionary
The project's Data Dictionary for star schema can be found [here](https://github.com/merettearula1/data-engineering-team-13/blob/main/Data_dictionary.md).



---
This project is developed as part of the Data Engineering 2026/27 fall course at the University of Tartu.
