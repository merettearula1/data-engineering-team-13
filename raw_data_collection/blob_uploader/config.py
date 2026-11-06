from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Settings:
    raw_data_dir: Path
    state_db: Path
    container: str
    interval_seconds: int
    storage_account_url: str | None
    manifest_blob: str
    block_target_bytes: int

    @classmethod
    def from_env(cls) -> "Settings":
        return cls(
            raw_data_dir=Path(os.getenv("RAW_DATA_DIR", "/app/data/raw")),
            state_db=Path(os.getenv("UPLOADER_STATE_DB", "/app/state/uploader.db")),
            container=os.getenv("AZURE_STORAGE_CONTAINER", "raw-data"),
            interval_seconds=int(os.getenv("UPLOAD_INTERVAL_SECONDS", "60")),
            storage_account_url=os.getenv("AZURE_STORAGE_ACCOUNT_URL"),
            manifest_blob=os.getenv("MANIFEST_BLOB", "manifests/manifest.json"),
            block_target_bytes=int(os.getenv("BLOCK_TARGET_BYTES", str(2 * 1024 * 1024))),
        )
