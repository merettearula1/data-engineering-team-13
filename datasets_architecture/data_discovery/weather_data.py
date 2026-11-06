import requests
import xml.etree.ElementTree as ET
import json
from datetime import datetime
from pathlib import Path

URL = "https://www.ilmateenistus.ee/ilma_andmed/xml/observations.php"

response = requests.get(URL)
response.raise_for_status()

root = ET.fromstring(response.content)

for station in root.findall(".//station"):
    if station.findtext("name") == "Tartu-Tõravere":

        fields = [
            "name",
            "wmocode",
            "longitude",
            "latitude",
            "phenomenon",
            "visibility",
            "precipitations",
            "airpressure",
            "relativehumidity",
            "airtemperature",
            "winddirection",
            "windspeed",
            "windspeedmax",
            "waterlevel",
            "waterlevel_eh2000",
            "watertemperature",
            "uvindex",
            "sunshineduration",
            "globalradiation"
        ]

        data = {
            field: station.findtext(field)
            for field in fields
        }

        data["snapshot_time"] = datetime.now().isoformat()

        folder = Path("weather_data/raw")
        folder.mkdir(parents=True, exist_ok=True)

        timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
        filename = folder / f"weather_{timestamp}.json"

        with open(filename, "w", encoding="utf-8") as file:
            json.dump(data, file, indent=4, ensure_ascii=False)

        print(f"Saved: {filename}")
        break