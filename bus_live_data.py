import asyncio
import json
from datetime import datetime, timezone
from pathlib import Path

import websockets


URL = "wss://api.ridango.com/rt-ws/vehicle-status"

SUBSCRIBE = {
    "regionId": 32,
    "topLeftCoordinates": {
        "longitude": 26.60,
        "latitude": 58.45,
    },
    "bottomRightCoordinates": {
        "longitude": 26.85,
        "latitude": 58.30,
    },
}

BASE_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = BASE_DIR / "bus_data"
RAW_DIR = OUTPUT_DIR / "raw"
OBSERVATIONS_FILE = OUTPUT_DIR / "realtime_vehicle_observations.jsonl"
COLLECTION_SECONDS = None

USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:156.0) "
    "Gecko/20100101 Firefox/156.0"
)


def utc_now() -> str:
    """Return the current UTC time as an ISO-8601 string."""
    return datetime.now(timezone.utc).isoformat()


def normalize_vehicle(vehicle: dict, fetched_at: str) -> dict:
    """Convert one Ridango vehicle object into one observation record."""
    trip = vehicle.get("trip") or {}
    position = vehicle.get("position") or {}

    return {
        "source": "ridango_tartu_realtime",
        "fetched_at": fetched_at,
        "source_update_time": vehicle.get("updateTime"),
        "device_id": vehicle.get("deviceId"),
        "location_id": vehicle.get("locationId"),
        "region_id": vehicle.get("regionId"),
        "trip_id": trip.get("tripId"),
        "route_short_name": trip.get("routeShortName"),
        "direction_id": trip.get("directionId"),
        "icon": trip.get("icon"),
        "latitude": position.get("latitude"),
        "longitude": position.get("longitude"),
        "speed": position.get("speed"),
        "bearing": position.get("bearing"),
        "raw_record": vehicle,
        "is_mock": False,
    }


async def collect() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    RAW_DIR.mkdir(parents=True, exist_ok=True)

    print(f"Connecting to {URL}...")
    print(f"Writing observations to: {OBSERVATIONS_FILE}")
    print("Press Ctrl+C to stop.\n")

    start_time = datetime.now(timezone.utc)
    total_observations = 0
    snapshot_number = 0

    async with websockets.connect(
        URL,
        origin="https://tartu.pilet.ee",
        user_agent_header=USER_AGENT,
        additional_headers={
            "Accept-Language": "en-US,en;q=0.9",
            "Cache-Control": "no-cache",
            "Pragma": "no-cache",
        },
        open_timeout=10,
    ) as ws:
        print("CONNECTED")

        await ws.send("{}")
        init_response = await ws.recv()
        print("INIT RESPONSE:", init_response)

        await ws.send(json.dumps(SUBSCRIBE))
        print("Vehicle subscription sent.\n")

        async for message in ws:
            fetched_at = utc_now()
            snapshot_number += 1
            raw_file = RAW_DIR / f"snapshot_{snapshot_number:06d}.json"

            try:
                data = json.loads(message)
            except json.JSONDecodeError:
                print("Received non-JSON message; saving raw text.")
                raw_file.write_text(message, encoding="utf-8")
                continue

            raw_file.write_text(
                json.dumps(data, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )

            if isinstance(data, dict):
                print("Control message:", data)
                continue

            if not isinstance(data, list):
                print(f"Unexpected message type: {type(data).__name__}")
                continue

            observations = [
                normalize_vehicle(vehicle, fetched_at)
                for vehicle in data
                if isinstance(vehicle, dict)
            ]

            with OBSERVATIONS_FILE.open("a", encoding="utf-8") as handle:
                for observation in observations:
                    handle.write(
                        json.dumps(
                            observation,
                            ensure_ascii=False,
                            separators=(",", ":"),
                        )
                        + "\n"
                    )

            total_observations += len(observations)

            print(
                f"[{fetched_at}] "
                f"vehicles={len(observations)} "
                f"total_observations={total_observations}"
            )

            for vehicle in observations[:5]:
                print(
                    f"  line={vehicle['route_short_name']} "
                    f"vehicle={vehicle['location_id']} "
                    f"lat={vehicle['latitude']} "
                    f"lon={vehicle['longitude']} "
                    f"speed={vehicle['speed']} "
                    f"source_time={vehicle['source_update_time']}"
                )

            print()

            if (
                COLLECTION_SECONDS is not None
                and (datetime.now(timezone.utc) - start_time).total_seconds()
                >= COLLECTION_SECONDS
            ):
                print("Collection time reached. Stopping.")
                break

    print("\nCollection finished.")
    print(f"Total normalized observations: {total_observations}")
    print(f"Raw snapshots: {RAW_DIR}")
    print(f"Observations: {OBSERVATIONS_FILE}")


if __name__ == "__main__":
    try:
        asyncio.run(collect())
    except KeyboardInterrupt:
        print("\nStopped by user.")
