"""UTC-partitioned, atomic persistence for unmodified source responses."""
from __future__ import annotations

import json
import os
import tempfile
import gzip
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from uuid import uuid4


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def utc_timestamp() -> str:
    return utc_now().isoformat().replace("+00:00", "Z")


def dated_dir(data_dir: Path, source: str, when: datetime | None = None) -> Path:
    moment = when or utc_now()
    path = data_dir / "raw" / source / f"date={moment.date().isoformat()}"
    path.mkdir(parents=True, exist_ok=True)
    return path


def unique_name(prefix: str, suffix: str, when: datetime | None = None) -> str:
    moment = when or utc_now()
    return f"{prefix}_{moment.strftime('%H%M%S_%f')}_{uuid4().hex[:8]}{suffix}"


def atomic_bytes(path: Path, contents: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".partial-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(contents)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
        os.chmod(path, 0o644)
    except BaseException:
        Path(temporary).unlink(missing_ok=True)
        raise


def write_json_snapshot(data_dir: Path, source: str, payload: Any, prefix: str = "snapshot") -> Path:
    directory = dated_dir(data_dir, source)
    destination = directory / unique_name(prefix, ".json")
    atomic_bytes(destination, json.dumps(payload, ensure_ascii=False, indent=2).encode("utf-8"))
    return destination


def write_xml_snapshot(data_dir: Path, source: str, payload: bytes) -> Path:
    directory = dated_dir(data_dir, source)
    destination = directory / unique_name("source_response", ".xml.gz")
    atomic_bytes(destination, gzip.compress(payload, mtime=0))
    return destination


def append_jsonl(data_dir: Path, source: str, record: dict[str, Any], filename: str = "observations.jsonl") -> Path:
    destination = dated_dir(data_dir, source) / filename
    line = json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n"
    with destination.open("a", encoding="utf-8") as handle:
        handle.write(line)
        handle.flush()
        os.fsync(handle.fileno())
    return destination


def append_jsonl_batch(
    data_dir: Path, source: str, records: list[dict[str, Any]], filename: str,
) -> Path:
    """Append related records through one handle, avoiding per-record files."""
    destination = dated_dir(data_dir, source) / filename
    if not records:
        return destination
    with destination.open("a", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")
        handle.flush()
        os.fsync(handle.fileno())
    return destination


def append_gzip_jsonl_batch(
    data_dir: Path, source: str, records: list[dict[str, Any]], filename: str,
) -> Path:
    """Append a batch as one valid gzip member; earlier batches survive a crash."""
    destination = dated_dir(data_dir, source) / filename
    if not records:
        return destination
    # Closing after each polling batch makes each member independently readable
    # if power is lost mid-write. gzip readers transparently read concatenated members.
    with gzip.open(destination, "at", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")
    return destination
