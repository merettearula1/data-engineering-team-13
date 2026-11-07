"""Reader for JSON snapshots, JSONL, and gzip-compressed JSONL files."""
from __future__ import annotations

import gzip
import io
import json


def read_records(data: bytes, path: str) -> list[dict]:
    """Return a list of JSON-object records from any collector file format."""
    if path.endswith(".jsonl.gz"):
        try:
            data = gzip.decompress(data)
        except OSError as exc:
            raise ValueError(f"{path}: invalid gzip file") from exc

    if path.endswith(".json"):
        try:
            document = json.loads(data)
        except json.JSONDecodeError as exc:
            raise ValueError(f"{path}: invalid JSON") from exc
        records = document if isinstance(document, list) else [document]
        if not all(isinstance(record, dict) for record in records):
            raise ValueError(f"{path}: JSON records must be objects")
        return records

    if not (path.endswith(".jsonl") or path.endswith(".jsonl.gz")):
        raise ValueError(f"{path}: unsupported file type")

    records = []
    for line_number, line in enumerate(io.BytesIO(data), start=1):
        if not line.strip():
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError as exc:
            raise ValueError(f"{path}, line {line_number}: invalid JSON") from exc
        if not isinstance(record, dict):
            raise ValueError(f"{path}, line {line_number}: record must be a JSON object")
        records.append(record)
    return records
