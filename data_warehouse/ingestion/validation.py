"""Small integrity and data-quality checks used before database loading."""
from __future__ import annotations

import hashlib
import json


def verify_file(data: bytes, entry: dict) -> None:
    """Verify the downloaded bytes against the manifest's size and SHA-256."""
    expected_size = entry.get("size_bytes")
    expected_checksum = entry.get("checksum")
    if len(data) != expected_size:
        raise ValueError(f"{entry['path']}: expected {expected_size} bytes, got {len(data)}")
    actual_checksum = hashlib.sha256(data).hexdigest()
    if actual_checksum != expected_checksum:
        raise ValueError(f"{entry['path']}: checksum does not match manifest")


def quality_check(records: list[dict], path: str) -> tuple[list[dict], int]:
    """Reject empty files and remove duplicate JSON records within one file."""
    if not records:
        raise ValueError(f"{path}: data-quality check failed: file has no records")
    unique_records = []
    seen = set()
    for record in records:
        fingerprint = json.dumps(record, sort_keys=True, separators=(",", ":"))
        if fingerprint not in seen:
            seen.add(fingerprint)
            unique_records.append(record)
    return unique_records, len(records) - len(unique_records)
