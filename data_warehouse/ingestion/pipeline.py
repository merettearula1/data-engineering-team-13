"""Coordinate the pipeline."""
from __future__ import annotations

import os
from datetime import date

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


def ingest(run_date: str | None = None, datasets: set[str] | None = None) -> dict:
    """Load selected collector datasets for an optional date partition."""
    if run_date:
        date.fromisoformat(run_date)

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
            if run_date and f"date={run_date}" not in path:
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
                          run_date=run_date, records=records)
            summary["loaded_files"] += 1
            summary["records_loaded"] += len(records)
            summary["duplicates_removed"] += duplicates
        return summary
    finally:
        engine.dispose()
