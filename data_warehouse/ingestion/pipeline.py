"""Coordinate the pipeline."""
from __future__ import annotations

import os
from datetime import date
import re

from sqlalchemy import create_engine

from ingestion.loader import already_loaded, load_file, setup_tables
from ingestion.readers import read_records
from ingestion.storage import download_bytes, download_manifest
from ingestion.validation import quality_check, verify_file

DATASETS = {
    "bus_departures",
    "bus_live",
    "bus_routes",
    "bus_stops",
    "bus_trip_stop_times",
    "bus_trips",
    "weather",
}


def ingest(start_date: str | None = None, end_date: str | None = None,
           datasets: set[str] | None = None) -> dict:
    """Load selected datasets within an optional inclusive date range."""
    if start_date:
        date.fromisoformat(start_date)
    if end_date:
        date.fromisoformat(end_date)
    if start_date and end_date and start_date > end_date:
        raise ValueError("start_date must not be later than end_date")

    manifest = download_manifest()
    database_url = os.environ["WAREHOUSE_DATABASE_URL"]
    engine = create_engine(database_url)
    summary = {"loaded_files": 0, "skipped_files": 0, "records_loaded": 0, "duplicates_removed": 0}

    try:
        with engine.begin() as connection:
            setup_tables(connection)

        for entry in manifest.get("files", []):
            path = entry.get("path", "")
            dataset = path.split("/", 1)[0]
            if dataset not in DATASETS or entry.get("status") not in {"active", "complete"}:
                continue
            if datasets and dataset not in datasets:
                continue
            if not path.endswith((".json", ".jsonl", ".jsonl.gz")):
                continue
            partition_match = re.search(r"(?:^|/)date=(\d{4}-\d{2}-\d{2})(?:/|$)", path)
            partition_date = partition_match.group(1) if partition_match else None
            if (
                partition_date is None
                or (start_date and partition_date < start_date)
                or (end_date and partition_date > end_date)
            ):
                continue
            checksum = entry.get("checksum")
            if not isinstance(checksum, str):
                continue

            with engine.connect() as connection:
                is_loaded = already_loaded(connection, path, checksum)
            if is_loaded:
                summary["skipped_files"] += 1
                continue

            data = download_bytes(path)
            verify_file(data, entry)
            records, duplicates = quality_check(read_records(data, path), path)

            with engine.begin() as connection:
                # Check again inside the transaction, making concurrent/rerun
                # executions idempotent.
                if already_loaded(connection, path, checksum):
                    summary["skipped_files"] += 1
                    continue
                load_file(connection, source=dataset, path=path, checksum=checksum,
                          run_date=partition_date, records=records)
            summary["loaded_files"] += 1
            summary["records_loaded"] += len(records)
            summary["duplicates_removed"] += duplicates
        return summary
    finally:
        engine.dispose()
