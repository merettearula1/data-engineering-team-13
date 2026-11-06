"""Read IDs from preserved API payloads without assuming a particular wrapper."""
from __future__ import annotations

import json
import gzip
from pathlib import Path
from typing import Any, Iterator


def records(payload: Any) -> list[dict[str, Any]]:
    if isinstance(payload, dict) and "payload" in payload:
        return records(payload["payload"])
    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, dict)]
    if isinstance(payload, dict):
        for key in ("data", "results", "items", "routes", "stops", "trips"):
            candidate = payload.get(key)
            if isinstance(candidate, list):
                return [item for item in candidate if isinstance(item, dict)]
    return []


def ids(payload: Any) -> list[str]:
    """Return identifiers from reference items and common trip-response shapes."""
    values: list[str] = []
    for item in records(payload):
        value = item.get("id", item.get("tripId", item.get("trip_id")))
        if value is not None:
            values.append(str(value))
    return list(dict.fromkeys(values))


def snapshot_payloads(data_dir: Path, source: str) -> Iterator[Any]:
    root = data_dir / "raw" / source
    if not root.exists():
        return
    for path in sorted(root.rglob("*.json"), reverse=True):
        try:
            yield json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
    for path in sorted(root.rglob("*.jsonl"), reverse=True):
        try:
            for line in path.read_text(encoding="utf-8").splitlines():
                yield json.loads(line)
        except (OSError, json.JSONDecodeError):
            continue
    for path in sorted(root.rglob("*.jsonl.gz"), reverse=True):
        try:
            with gzip.open(path, "rt", encoding="utf-8") as handle:
                for line in handle:
                    yield json.loads(line)
        except (OSError, json.JSONDecodeError):
            continue


def discovered_ids(data_dir: Path, source: str) -> list[str]:
    found: list[str] = []
    for payload in snapshot_payloads(data_dir, source):
        found.extend(ids(payload))
    return list(dict.fromkeys(found))
