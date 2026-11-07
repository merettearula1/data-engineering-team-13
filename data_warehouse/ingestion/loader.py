"""PostgreSQL setup and idempotent loading for the small Bronze layer."""
from __future__ import annotations

import json

from sqlalchemy import text


def setup_tables(connection) -> None:
    connection.execute(text("CREATE SCHEMA IF NOT EXISTS bronze"))
    connection.execute(text("""
        CREATE TABLE IF NOT EXISTS bronze.ingested_files (
            blob_path TEXT NOT NULL,
            checksum TEXT NOT NULL,
            source_name TEXT NOT NULL,
            run_date DATE,
            records_loaded INTEGER NOT NULL,
            loaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            PRIMARY KEY (blob_path, checksum)
        )
    """))
    connection.execute(text("""
        CREATE TABLE IF NOT EXISTS bronze.raw_events (
            id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            source_name TEXT NOT NULL,
            blob_path TEXT NOT NULL,
            checksum TEXT NOT NULL,
            record_number INTEGER NOT NULL,
            payload JSONB NOT NULL,
            loaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            UNIQUE (blob_path, checksum, record_number)
        )
    """))


def already_loaded(connection, path: str, checksum: str) -> bool:
    return connection.execute(text("""
        SELECT 1 FROM bronze.ingested_files
        WHERE blob_path = :path AND checksum = :checksum
    """), {"path": path, "checksum": checksum}).first() is not None


def load_file(connection, *, source: str, path: str, checksum: str,
              run_date: str | None, records: list[dict]) -> None:
    connection.execute(text("""
        INSERT INTO bronze.raw_events (source_name, blob_path, checksum, record_number, payload)
        VALUES (:source, :path, :checksum, :number, CAST(:payload AS JSONB))
    """), [{"source": source, "path": path, "checksum": checksum,
              "number": number, "payload": json.dumps(record)}
             for number, record in enumerate(records, start=1)])
    connection.execute(text("""
        INSERT INTO bronze.ingested_files (blob_path, checksum, source_name, run_date, records_loaded)
        VALUES (:path, :checksum, :source, :run_date, :count)
    """), {"path": path, "checksum": checksum, "source": source,
           "run_date": run_date, "count": len(records)})
