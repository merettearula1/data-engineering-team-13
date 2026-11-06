from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class FileState:
    generation: str
    offset: int = 0
    blocks: list[str] = field(default_factory=list)
    checksums: list[str] = field(default_factory=list)
    record_count: int = 0
    status: str = "active"
    last_size: int = 0
    updated_at: str | None = None


class StateStore:
    def __init__(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        self.connection = sqlite3.connect(path)
        self.connection.execute(
            """CREATE TABLE IF NOT EXISTS files (
                path TEXT PRIMARY KEY, generation TEXT NOT NULL, offset INTEGER NOT NULL,
                blocks TEXT NOT NULL, checksums TEXT NOT NULL, record_count INTEGER NOT NULL,
                status TEXT NOT NULL, last_size INTEGER NOT NULL, updated_at TEXT
            )"""
        )
        self.connection.commit()

    def get(self, path: str) -> FileState | None:
        row = self.connection.execute(
            "SELECT generation, offset, blocks, checksums, record_count, status, last_size, updated_at "
            "FROM files WHERE path = ?", (path,)
        ).fetchone()
        if row is None:
            return None
        return FileState(row[0], row[1], json.loads(row[2]), json.loads(row[3]), row[4], row[5], row[6], row[7])

    def save(self, path: str, state: FileState) -> None:
        self.connection.execute(
            """INSERT INTO files(path, generation, offset, blocks, checksums, record_count, status, last_size, updated_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
               ON CONFLICT(path) DO UPDATE SET generation=excluded.generation, offset=excluded.offset,
               blocks=excluded.blocks, checksums=excluded.checksums, record_count=excluded.record_count,
               status=excluded.status, last_size=excluded.last_size, updated_at=excluded.updated_at""",
            (path, state.generation, state.offset, json.dumps(state.blocks),
             json.dumps(state.checksums), state.record_count, state.status, state.last_size, state.updated_at),
        )
        self.connection.commit()

    def all(self) -> list[tuple[str, FileState]]:
        rows = self.connection.execute("SELECT path, generation, offset, blocks, checksums, "
                                       "record_count, status, last_size, updated_at FROM files").fetchall()
        return [
            (row[0], FileState(row[1], row[2], json.loads(row[3]), json.loads(row[4]),
                               row[5], row[6], row[7], row[8]))
            for row in rows
        ]

    def close(self) -> None:
        self.connection.close()
