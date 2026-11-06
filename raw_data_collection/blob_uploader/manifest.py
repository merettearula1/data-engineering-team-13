from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


class Manifest:
    def __init__(self) -> None:
        self.files: dict[str, dict[str, Any]] = {}

    def update(self, path: str, size: int, checksum: str, status: str, record_count: int) -> None:
        self.files[path] = {
            "path": path, "size_bytes": size, "checksum_algorithm": "sha256",
            "checksum": checksum, "record_count": record_count, "status": status,
            "last_updated": utc_now(),
        }

    def serialize(self) -> bytes:
        return json.dumps({"version": 1, "generated_at": utc_now(),
                           "files": list(self.files.values())}, indent=2).encode()
