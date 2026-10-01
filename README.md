# Tartu Transit Analytics using live bus data and live weather data

### Data Sources

#### Public Transport

Bus movement and schedule data is queried from [tartu.pilet.ee] (https://tartu.pilet.ee/et/explore?selectedTab=routes) and is used to describe:

* Bus locations and movements
* Routes
* Bus stops
* Scheduled trips and times

![img](bus_data_sources_diagram.png)

#### Weather

Weather observations are retrieved from [ilmateenistus.ee](https://www.ilmateenistus.ee/teenused/ilmainfo/eesti-vaatlusandmed-xml/).

The project uses observations from the Tartu-Tõravere weather station.


### Data Dictionary
The project's Data Dictionary can be found [here](https://github.com/merettearula1/data-engineering-team-13/blob/main/Data_dictionary.md).



---
This project is developed as part of the Data Engineering 2026/27 fall course at the University of Tartu.