from __future__ import annotations

import hashlib
import json
import logging
import os
import time
from pathlib import Path

from .azure_storage import AzureBlobStore, BlobStore, block_id
from .config import Settings
from .gzip_members import read_complete_members
from .manifest import Manifest, utc_now
from .state import FileState, StateStore

LOGGER = logging.getLogger("blob_uploader")


def generation_for(path: Path) -> str:
    stat = path.stat()
    return f"{stat.st_dev}:{stat.st_ino}:{stat.st_ctime_ns}"


class Uploader:
    def __init__(self, settings: Settings, store: BlobStore) -> None:
        self.settings = settings
        self.store = store
        self.state = StateStore(settings.state_db)
        self.manifest = Manifest()

    def scan(self) -> None:
        LOGGER.info("Starting upload scan")
        if not self.settings.raw_data_dir.exists():
            LOGGER.warning("Raw data directory does not exist: %s", self.settings.raw_data_dir)
            return
        for relative, state in self.state.all():
            path = self.settings.raw_data_dir / relative
            if path.is_file() and path.stat().st_size >= state.offset:
                checksum = hashlib.sha256(path.read_bytes()[:state.offset]).hexdigest()
                self.manifest.update(relative, state.offset, checksum, state.status, state.record_count)
        for path in sorted(p for p in self.settings.raw_data_dir.rglob("*") if p.is_file()):
            try:
                self.sync_file(path)
            except Exception:
                LOGGER.exception("Upload failed for %s; will retry", path)
        if self.manifest.files:
            self.store.upload_blob(self.settings.manifest_blob, self.manifest.serialize())
            LOGGER.info("Manifest updated")

    def sync_file(self, path: Path) -> None:
        relative = path.relative_to(self.settings.raw_data_dir).as_posix()
        identity = generation_for(path)
        state = self.state.get(relative)
        if state is None or state.generation != identity or path.stat().st_size < state.offset:
            state = FileState(identity)
        if path.suffix == ".gz" and path.name.endswith(".jsonl.gz"):
            self._sync_gzip(path, relative, state)
        elif path.suffix == ".jsonl":
            self._sync_jsonl(path, relative, state)
        else:
            self._sync_snapshot(path, relative, state)

    def _commit_append(self, relative: str, state: FileState, data: bytes, record_count: int) -> None:
        sequence = len(state.blocks)
        identifier = block_id(relative, state.generation, sequence)
        checksum = hashlib.sha256(data).hexdigest()
        self.store.stage_block(relative, identifier, data, checksum)
        self.store.commit_block_list(relative, state.blocks + [identifier])
        state.blocks.append(identifier)
        state.checksums.append(checksum)
        state.offset += len(data)
        state.record_count += record_count
        state.last_size = state.offset
        state.updated_at = utc_now()
        self.state.save(relative, state)
        self.manifest.update(
            relative, state.offset, self._committed_checksum(relative, state),
            state.status, state.record_count,
        )
        LOGGER.info("%s: committed %d bytes at offset %d", relative, len(data), state.offset)

    def _committed_checksum(self, relative: str, state: FileState) -> str:
        path = self.settings.raw_data_dir / relative
        return hashlib.sha256(path.read_bytes()[:state.offset]).hexdigest()

    def _sync_gzip(self, path: Path, relative: str, state: FileState) -> None:
        data = path.read_bytes()
        members, _ = read_complete_members(data, state.offset)
        if not members:
            state.last_size = len(data)
            self.state.save(relative, state)
            return
        chunks: list[bytes] = []
        records = 0
        for member in members:
            chunks.append(member.compressed)
            records += member.record_count
            if sum(map(len, chunks)) >= self.settings.block_target_bytes:
                self._commit_append(relative, state, b"".join(chunks), records)
                chunks, records = [], 0
        if chunks:
            self._commit_append(relative, state, b"".join(chunks), records)

    def _sync_jsonl(self, path: Path, relative: str, state: FileState) -> None:
        data = path.read_bytes()
        complete_end = data.rfind(b"\n", state.offset) + 1
        if complete_end <= state.offset:
            state.last_size = len(data)
            self.state.save(relative, state)
            return
        payload = data[state.offset:complete_end]
        records = 0
        for line in payload.splitlines():
            if line.strip():
                json.loads(line)
                records += 1
        self._commit_append(relative, state, payload, records)
        state.last_size = len(data)
        self.state.save(relative, state)

    def _sync_snapshot(self, path: Path, relative: str, state: FileState) -> None:
        data = path.read_bytes()
        checksum = hashlib.sha256(data).hexdigest()
        if state.checksums == [checksum] and state.offset == len(data):
            return
        identifier = block_id(relative, state.generation, 0)
        self.store.stage_block(relative, identifier, data, checksum)
        self.store.commit_block_list(relative, [identifier])
        state.blocks, state.checksums = [identifier], [checksum]
        state.offset, state.last_size, state.updated_at = len(data), len(data), utc_now()
        state.status = "complete"
        self.state.save(relative, state)
        self.manifest.update(relative, len(data), checksum, state.status, state.record_count)
        LOGGER.info("%s: snapshot committed (%d bytes)", relative, len(data))


def main() -> None:
    logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"),
                        format="%(asctime)s %(levelname)s %(message)s")
    settings = Settings.from_env()
    if not settings.storage_account_url:
        raise RuntimeError("AZURE_STORAGE_ACCOUNT_URL is required")
    uploader = Uploader(settings, AzureBlobStore(settings.storage_account_url, settings.container))
    try:
        while True:
            uploader.scan()
            time.sleep(settings.interval_seconds)
    finally:
        uploader.state.close()


if __name__ == "__main__":
    main()
