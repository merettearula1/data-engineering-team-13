"""Resilient Ridango vehicle-status WebSocket collector."""
from __future__ import annotations

import asyncio
import json
import logging

import websockets

from common.config import settings
from common.storage import append_gzip_jsonl_batch, utc_timestamp, write_json_snapshot

URL = "wss://api.ridango.com/rt-ws/vehicle-status"
SUBSCRIBE = {"regionId": 32, "topLeftCoordinates": {"longitude": 26.60, "latitude": 58.45}, "bottomRightCoordinates": {"longitude": 26.85, "latitude": 58.30}}
USER_AGENT = "Mozilla/5.0 (compatible; Tartu-data-collection/1.0)"
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
LOGGER = logging.getLogger(__name__)


async def collect_forever() -> None:
    config = settings()
    delay = 1
    count = 0
    while True:
        try:
            LOGGER.info("connecting to vehicle status WebSocket")
            async with websockets.connect(URL, origin="https://tartu.pilet.ee", user_agent_header=USER_AGENT, open_timeout=10) as websocket:
                await websocket.send("{}")
                await websocket.recv()  # Required initialization reply from the existing collector.
                await websocket.send(json.dumps(SUBSCRIBE))
                LOGGER.info("connected and subscribed")
                delay = 1
                async for message in websocket:
                    fetched_at = utc_timestamp()
                    try:
                        payload = json.loads(message)
                    except json.JSONDecodeError:
                        write_json_snapshot(config.data_dir, "bus_live", {"fetched_at": fetched_at, "raw_text": message}, "malformed")
                        LOGGER.warning("saved malformed WebSocket message")
                        continue
                    append_gzip_jsonl_batch(config.data_dir, "bus_live", [{"fetched_at": fetched_at, "payload": payload}], "messages.jsonl.gz")
                    if not isinstance(payload, list):
                        LOGGER.info("received control/unexpected message type %s", type(payload).__name__)
                        continue
                    vehicle_count = sum(isinstance(item, dict) for item in payload)
                    count += vehicle_count
                    LOGGER.info("received=%d total_observations=%d", vehicle_count, count)
        except asyncio.CancelledError:
            raise
        except Exception as error:
            LOGGER.warning("WebSocket disconnected/error: %s; reconnecting in %ss", error, delay)
            await asyncio.sleep(delay)
            delay = min(delay * 2, config.websocket_max_backoff_seconds)


if __name__ == "__main__":
    asyncio.run(collect_forever())
