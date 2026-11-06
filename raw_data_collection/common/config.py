"""Configuration read from environment variables with safe defaults."""
from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


def _integer(name: str, default: int) -> int:
    value = os.getenv(name, str(default))
    try:
        return int(value)
    except ValueError:
        raise ValueError(f"{name} must be an integer, got {value!r}") from None


@dataclass(frozen=True)
class Settings:
    data_dir: Path
    bus_api_base_url: str
    weather_interval_seconds: int
    reference_interval_seconds: int
    timetable_interval_seconds: int
    departures_interval_seconds: int
    http_timeout_seconds: int
    http_retries: int
    http_backoff_seconds: int
    request_concurrency: int
    websocket_max_backoff_seconds: int
    dependency_retry_seconds: int


def settings() -> Settings:
    data_dir = Path(os.getenv("DATA_DIR", "/app/data")).resolve()
    return Settings(
        data_dir=data_dir,
        bus_api_base_url=os.getenv("BUS_API_BASE_URL", "").rstrip("/"),
        weather_interval_seconds=_integer("WEATHER_INTERVAL_SECONDS", 600),
        reference_interval_seconds=_integer("REFERENCE_INTERVAL_SECONDS", 86400),
        timetable_interval_seconds=_integer("TIMETABLE_INTERVAL_SECONDS", 86400),
        departures_interval_seconds=_integer("DEPARTURES_INTERVAL_SECONDS", 300),
        http_timeout_seconds=_integer("HTTP_TIMEOUT_SECONDS", 20),
        http_retries=_integer("HTTP_RETRIES", 3),
        http_backoff_seconds=_integer("HTTP_BACKOFF_SECONDS", 2),
        request_concurrency=_integer("BUS_REQUEST_CONCURRENCY", _integer("MAX_CONCURRENT_REQUESTS", 8)),
        websocket_max_backoff_seconds=_integer("WEBSOCKET_MAX_BACKOFF_SECONDS", 60),
        dependency_retry_seconds=_integer("DEPENDENCY_RETRY_SECONDS", 60),
    )
