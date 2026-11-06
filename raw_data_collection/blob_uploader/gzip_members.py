from __future__ import annotations

import json
import zlib
from dataclasses import dataclass


@dataclass(frozen=True)
class GzipMember:
    start: int
    end: int
    compressed: bytes
    record_count: int


def _validate_jsonl(payload: bytes) -> int:
    if not payload:
        raise ValueError("gzip member is empty")
    if not payload.endswith(b"\n"):
        raise ValueError("gzip member does not end with a newline")
    count = 0
    for line in payload.splitlines():
        if not line.strip():
            raise ValueError("gzip member contains an empty record")
        json.loads(line)
        count += 1
    return count


def read_complete_members(data: bytes, offset: int = 0) -> tuple[list[GzipMember], int]:
    """Return complete members and the first byte that may still be incomplete."""
    members: list[GzipMember] = []
    cursor = offset
    while cursor < len(data):
        decompressor = zlib.decompressobj(16 + zlib.MAX_WBITS)
        try:
            payload = decompressor.decompress(data[cursor:])
            payload += decompressor.flush()
        except zlib.error:
            break
        if not decompressor.eof:
            break
        end = len(data) - len(decompressor.unused_data)
        try:
            record_count = _validate_jsonl(payload)
        except (ValueError, json.JSONDecodeError):
            raise ValueError(f"invalid JSONL in gzip member at byte {cursor}") from None
        members.append(GzipMember(cursor, end, data[cursor:end], record_count))
        if end <= cursor:
            raise ValueError("gzip parser made no progress")
        cursor = end
    return members, cursor
