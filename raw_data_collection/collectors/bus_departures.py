"""Bounded concurrent polling of upcoming departures for every discovered stop."""
from __future__ import annotations

import concurrent.futures
import logging
import time
from urllib.parse import quote

from common.config import settings
from common.discovery import discovered_ids
from common.http import endpoint, get_json
from common.storage import append_gzip_jsonl_batch, utc_timestamp

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
LOGGER = logging.getLogger(__name__)


def _one(stop_id: str) -> dict[str, object]:
    config = settings()
    path = f"/v1/stops/{quote(stop_id, safe='')}/stoptimes"
    payload = get_json(endpoint(config, path), config)
    return {"stop_id": stop_id, "endpoint": path, "fetched_at": utc_timestamp(), "payload": payload}


def collect_once() -> None:
    config = settings()
    if not config.bus_api_base_url:
        LOGGER.error("BUS_API_BASE_URL is required; departures collection is waiting")
        return
    stop_ids = discovered_ids(config.data_dir, "bus_stops")
    if not stop_ids:
        LOGGER.warning("no valid stop snapshot yet; waiting for bus-reference")
        return
    failures = 0
    responses: list[dict[str, object]] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=config.request_concurrency) as pool:
        futures = {pool.submit(_one, stop_id): stop_id for stop_id in stop_ids}
        for future in concurrent.futures.as_completed(futures):
            try:
                responses.append(future.result())
            except Exception:
                failures += 1
                LOGGER.exception("stop failed: %s", futures[future])
    append_gzip_jsonl_batch(config.data_dir, "bus_departures", responses, "responses.jsonl.gz")
    LOGGER.info("departures cycle: stops=%d succeeded=%d failed=%d", len(stop_ids), len(stop_ids) - failures, failures)


def main() -> None:
    while True:
        collect_once()
        time.sleep(settings().departures_interval_seconds)


if __name__ == "__main__":
    main()
