"""Small retrying HTTP client; callers retain each source response unchanged."""
from __future__ import annotations

import logging
import time
from typing import Any

import requests

from common.config import Settings

LOGGER = logging.getLogger(__name__)


def get_json(url: str, config: Settings, params: dict[str, str] | None = None) -> Any:
    last_error: Exception | None = None
    for attempt in range(1, config.http_retries + 1):
        try:
            response = requests.get(url, params=params, timeout=config.http_timeout_seconds)
            response.raise_for_status()
            return response.json()
        except (requests.RequestException, ValueError) as error:
            last_error = error
            if attempt < config.http_retries:
                delay = config.http_backoff_seconds * 2 ** (attempt - 1)
                LOGGER.warning("GET %s failed (attempt %d/%d): %s; retrying in %ss", url, attempt, config.http_retries, error, delay)
                time.sleep(delay)
    raise RuntimeError(f"GET {url} failed after {config.http_retries} attempts") from last_error


def get_bytes(url: str, config: Settings) -> bytes:
    """Fetch an opaque source document with the same bounded retry policy."""
    last_error: Exception | None = None
    for attempt in range(1, config.http_retries + 1):
        try:
            response = requests.get(url, timeout=config.http_timeout_seconds)
            response.raise_for_status()
            return response.content
        except requests.RequestException as error:
            last_error = error
            if attempt < config.http_retries:
                delay = config.http_backoff_seconds * 2 ** (attempt - 1)
                LOGGER.warning("GET %s failed (attempt %d/%d): %s; retrying in %ss", url, attempt, config.http_retries, error, delay)
                time.sleep(delay)
    raise RuntimeError(f"GET {url} failed after {config.http_retries} attempts") from last_error


def endpoint(config: Settings, path: str) -> str:
    if not config.bus_api_base_url:
        raise RuntimeError("BUS_API_BASE_URL is not configured; see .env.example and README")
    return f"{config.bus_api_base_url}{path}"
