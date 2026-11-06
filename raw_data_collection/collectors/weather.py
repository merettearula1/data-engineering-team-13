from __future__ import annotations

import logging
import time
import xml.etree.ElementTree as ET
from common.config import settings
from common.http import get_bytes
from common.storage import append_jsonl, utc_timestamp

URL = "https://www.ilmateenistus.ee/ilma_andmed/xml/observations.php"
STATION = "Tartu-Tõravere"
FIELDS = ("name", "wmocode", "longitude", "latitude", "phenomenon", "visibility", "precipitations", "airpressure", "relativehumidity", "airtemperature", "winddirection", "windspeed", "windspeedmax", "waterlevel", "waterlevel_eh2000", "watertemperature", "uvindex", "sunshineduration", "globalradiation")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
LOGGER = logging.getLogger(__name__)


def collect_once() -> None:
    config = settings()
    source_xml = get_bytes(URL, config)
    fetched_at = utc_timestamp()
    root = ET.fromstring(source_xml)
    station = next((node for node in root.findall(".//station") if node.findtext("name") == STATION), None)
    if station is None:
        raise RuntimeError(f"Station {STATION!r} was not present in the XML response")
    # XML represents unavailable measurements as empty text; JSONL represents
    # those explicitly as null.
    observation = {
        field: (value if (value := station.findtext(field)) not in (None, "") else None)
        for field in FIELDS
    }
    # The API's root timestamp is retained when supplied; all absent values remain null.
    observation.update(source="estonian_environment_agency", fetched_at=fetched_at, source_observation_time=root.get("timestamp") or root.findtext("timestamp"))
    append_jsonl(config.data_dir, "weather", observation)
    LOGGER.info("stored weather observation for %s", STATION)


def main() -> None:
    while True:
        try:
            collect_once()
        except Exception:
            LOGGER.exception("weather collection cycle failed")
        time.sleep(settings().weather_interval_seconds)


if __name__ == "__main__":
    main()
