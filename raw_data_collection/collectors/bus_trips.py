"""Collect each route's raw trip response after route IDs become available."""
from __future__ import annotations

import concurrent.futures
import logging
import time
from urllib.parse import quote

from common.config import settings
from common.discovery import discovered_ids
from common.http import endpoint, get_json
from common.storage import append_jsonl_batch, utc_timestamp

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
LOGGER = logging.getLogger(__name__)


def _one(route_id: str) -> dict[str, object]:
    config = settings()
    path = f"/v1/routes/{quote(route_id, safe='')}/trips"
    payload = get_json(endpoint(config, path), config)
    return {"route_id": route_id, "endpoint": path, "fetched_at": utc_timestamp(), "pagination": None, "payload": payload}


def collect_once() -> bool:
    config = settings()
    if not config.bus_api_base_url:
        LOGGER.error("BUS_API_BASE_URL is required; route-trip collection is waiting")
        return False
    route_ids = discovered_ids(config.data_dir, "bus_routes")
    if not route_ids:
        LOGGER.warning("no valid route snapshot yet; waiting for bus-reference")
        return False
    failures = 0
    responses: list[dict[str, object]] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=config.request_concurrency) as pool:
        futures = {pool.submit(_one, route_id): route_id for route_id in route_ids}
        for future in concurrent.futures.as_completed(futures):
            try:
                responses.append(future.result())
            except Exception:
                failures += 1
                LOGGER.exception("route failed: %s", futures[future])
    append_jsonl_batch(config.data_dir, "bus_trips", responses, "responses.jsonl")
    LOGGER.info("route trips complete: discovered=%d succeeded=%d failed=%d", len(route_ids), len(route_ids) - failures, failures)
    return True


def main() -> None:
    while True:
        completed = collect_once()
        config = settings()
        time.sleep(config.timetable_interval_seconds if completed else config.dependency_retry_seconds)


if __name__ == "__main__":
    main()
