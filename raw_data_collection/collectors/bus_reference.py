"""Daily snapshots of the configured stops and routes endpoints."""
from __future__ import annotations

import logging
import time

from common.config import settings
from common.http import endpoint, get_json
from common.storage import utc_timestamp, write_json_snapshot

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
LOGGER = logging.getLogger(__name__)


def collect_once() -> None:
    config = settings()
    for path, source in (("/v1/stops", "bus_stops"), ("/v1/routes", "bus_routes")):
        try:
            url = endpoint(config, path)
            payload = get_json(url, config)
            # Fetch metadata belongs beside its response, not in a second file.
            write_json_snapshot(config.data_dir, source, {"endpoint": path, "fetched_at": utc_timestamp(), "payload": payload})
            LOGGER.info("saved %s", path)
        except Exception:
            LOGGER.exception("reference endpoint failed: %s", path)


def main() -> None:
    while True:
        collect_once()
        time.sleep(settings().reference_interval_seconds)


if __name__ == "__main__":
    main()
