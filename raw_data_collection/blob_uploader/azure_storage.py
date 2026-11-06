from __future__ import annotations

import base64
import hashlib
from typing import Protocol


class BlobStore(Protocol):
    def stage_block(self, blob_name: str, block_id: str, data: bytes, sha256: str) -> None: ...
    def commit_block_list(self, blob_name: str, block_ids: list[str]) -> None: ...
    def upload_blob(self, blob_name: str, data: bytes, overwrite: bool = True) -> None: ...


def block_id(blob_name: str, generation: str, sequence: int) -> str:
    value = f"{blob_name}\0{generation}\0{sequence}".encode()
    return base64.b64encode(hashlib.sha256(value).digest()[:24]).decode()


class AzureBlobStore:
    def __init__(self, account_url: str, container: str) -> None:
        try:
            from azure.identity import DefaultAzureCredential
            from azure.storage.blob import BlobServiceClient
        except ImportError as exc:
            raise RuntimeError("Azure uploader dependencies are not installed") from exc
        service = BlobServiceClient(account_url, credential=DefaultAzureCredential())
        self.container = service.get_container_client(container)

    def stage_block(self, blob_name: str, block_id: str, data: bytes, sha256: str) -> None:
        self.container.get_blob_client(blob_name).stage_block(
            block_id=block_id, data=data,
            validate_content=True,
        )
        if hashlib.sha256(data).hexdigest() != sha256:
            raise IOError(f"local checksum changed while staging {blob_name}")

    def commit_block_list(self, blob_name: str, block_ids: list[str]) -> None:
        self.container.get_blob_client(blob_name).commit_block_list(block_ids)

    def upload_blob(self, blob_name: str, data: bytes, overwrite: bool = True) -> None:
        self.container.upload_blob(name=blob_name, data=data, overwrite=overwrite)
