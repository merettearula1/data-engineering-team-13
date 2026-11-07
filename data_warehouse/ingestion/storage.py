"""Download public files from the raw-data Blob container."""
from __future__ import annotations

import json
import os
from urllib.parse import quote
from urllib.request import urlopen


BASE_URL = os.getenv("RAW_DATA_URL", "https://tarturawdata.blob.core.windows.net/raw-data")


def download_bytes(blob_path: str) -> bytes:
    """Download one public blob. Blob paths may contain slashes, but not '..'."""
    if not blob_path or ".." in blob_path.split("/"):
        raise ValueError(f"Unsafe blob path: {blob_path!r}")
    url = f"{BASE_URL.rstrip('/')}/{quote(blob_path, safe='/')}"
    with urlopen(url, timeout=30) as response:
        return response.read()


def download_manifest() -> dict:
    """Return the collector's manifest as a Python dictionary."""
    try:
        return json.loads(download_bytes("manifests/manifest.json"))
    except json.JSONDecodeError as exc:
        raise ValueError("Manifest is not valid JSON") from exc
