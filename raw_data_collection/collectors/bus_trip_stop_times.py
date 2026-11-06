"""Bounded concurrent collection of schedules for trip IDs discovered from routes."""
from __future__ import annotations

import concurrent.futures
import logging
import time

from common.config import settings
from common.discovery import discovered_ids
from common.http import endpoint, get_json
from common.storage import append_gzip_jsonl_batch, utc_timestamp

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
LOGGER = logging.getLogger(__name__)


def _one(trip_id: str) -> dict[str, object]:
    config = settings()
    path = "/v1/trips/stoptimes"
    payload = get_json(endpoint(config, path), config, params={"tripId": trip_id})
    return {"trip_id": trip_id, "endpoint": path, "fetched_at": utc_timestamp(), "pagination": None, "payload": payload}


def collect_once() -> bool:
    config = settings()
    if not config.bus_api_base_url:
        LOGGER.error("BUS_API_BASE_URL is required; trip stop-time collection is waiting")
        return False
    trip_ids = discovered_ids(config.data_dir, "bus_trips")
    if not trip_ids:
        LOGGER.warning("no valid route-trip snapshot yet; waiting for bus-trips")
        return False
    failures = 0
    responses: list[dict[str, object]] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=config.request_concurrency) as pool:
        futures = {pool.submit(_one, trip_id): trip_id for trip_id in trip_ids}
        for future in concurrent.futures.as_completed(futures):
            try:
                responses.append(future.result())
            except Exception:
                failures += 1
                LOGGER.exception("trip failed: %s", futures[future])
    append_gzip_jsonl_batch(config.data_dir, "bus_trip_stop_times", responses, "responses.jsonl.gz")
    LOGGER.info("trip schedules complete: discovered=%d succeeded=%d failed=%d", len(trip_ids), len(trip_ids) - failures, failures)
    return True


def main() -> None:
    while True:
        completed = collect_once()
        config = settings()
        time.sleep(config.timetable_interval_seconds if completed else config.dependency_retry_seconds)


if __name__ == "__main__":
    main()
