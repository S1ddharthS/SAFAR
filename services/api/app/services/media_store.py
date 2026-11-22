"""Storage adapter for private trip media.

The application persists only a canonical ``/media/{trip_id}/{filename}``
reference. HMAC signing stays in :mod:`app.services.media`; this module owns
the byte storage behind that reference so a future private object-store adapter
can replace the local filesystem without changing API contracts.

No external service is contacted by the bundled backends. The ``memory``
backend exists for unit tests and local verification only.
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from pathlib import Path
from typing import AsyncIterator, Protocol
from urllib.parse import parse_qs, urlsplit

from app.core.config import settings

TRIP_ID_PATTERN = re.compile(r"^[0-9a-f]{32}$")
MEDIA_NAME_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")


class MediaStoreError(Exception):
    """Base class for storage failures that map to a safe API response."""


class MediaValidationError(MediaStoreError):
    """The trip id or filename is not a valid media key."""


class MediaTooLargeError(MediaStoreError):
    """The upload exceeded the configured byte limit."""


@dataclass(frozen=True)
class MediaKey:
    trip_id: str
    filename: str

    @property
    def path(self) -> str:
        return f"/media/{self.trip_id}/{self.filename}"


@dataclass(frozen=True)
class MediaStorageStats:
    backend: str
    storage_dir: str | None
    total_files: int
    total_bytes: int


def parse_media_key(trip_id: str, filename: str) -> MediaKey:
    """Validate a storage key. Never accept separators or traversal segments."""
    if not TRIP_ID_PATTERN.match(trip_id or "") or not MEDIA_NAME_PATTERN.match(
        filename or ""
    ):
        raise MediaValidationError("Invalid media key")
    return MediaKey(trip_id=trip_id, filename=filename)


def parse_media_url(url: str | None, expected_trip_id: str | None = None) -> MediaKey:
    """Extract a canonical key from a signed or unsigned local media URL."""
    if not url:
        raise MediaValidationError("Missing media URL")
    parts = urlsplit(url)
    if parts.scheme or parts.netloc or not parts.path.startswith("/media/"):
        raise MediaValidationError("Media is not a local SAFAR upload")
    remainder = parts.path[len("/media/"):]
    trip_id, separator, filename = remainder.partition("/")
    if not separator or not trip_id or not filename:
        raise MediaValidationError("Invalid media URL")
    if expected_trip_id and trip_id != expected_trip_id:
        raise MediaValidationError("Media belongs to another trip")
    if not MEDIA_NAME_PATTERN.match(filename):
        raise MediaValidationError("Invalid media name")
    key = parse_media_key(trip_id, filename)
    # Query values are intentionally ignored here; callers still verify the
    # signature before serving or processing the file.
    parse_qs(parts.query)
    return key


class MediaStore(Protocol):
    """Contract implemented by local and future private object stores."""

    backend_name: str

    def ensure_ready(self) -> None: ...

    async def save(
        self,
        trip_id: str,
        filename: str,
        chunks: AsyncIterator[bytes],
        max_bytes: int,
    ) -> int: ...

    def read_bytes(self, trip_id: str, filename: str) -> bytes: ...

    def local_path(self, trip_id: str, filename: str) -> Path | None:
        """Return a directly readable path, or None for remote backends."""

    def delete(self, trip_id: str, filename: str) -> bool: ...

    def stats(self) -> MediaStorageStats: ...


class LocalMediaStore:
    """Filesystem implementation with strict key validation and atomic writes."""

    backend_name = "local"

    def __init__(self, root: Path) -> None:
        self.root = root.resolve()

    def ensure_ready(self) -> None:
        self.root.mkdir(parents=True, exist_ok=True)

    def _target(self, trip_id: str, filename: str) -> Path:
        key = parse_media_key(trip_id, filename)
        target = (self.root / key.trip_id / key.filename).resolve()
        if self.root not in target.parents:
            raise MediaValidationError("Media path escapes storage root")
        return target

    async def save(
        self,
        trip_id: str,
        filename: str,
        chunks: AsyncIterator[bytes],
        max_bytes: int,
    ) -> int:
        target = self._target(trip_id, filename)
        if target.exists():
            raise MediaValidationError("Media object already exists")
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = target.with_name(f".{filename}.{os.getpid()}.partial")
        size = 0
        try:
            with temporary.open("xb") as handle:
                async for chunk in chunks:
                    size += len(chunk)
                    if size > max_bytes:
                        raise MediaTooLargeError("Media files are limited to 25 MB")
                    handle.write(chunk)
            os.replace(temporary, target)
        except BaseException:
            temporary.unlink(missing_ok=True)
            raise
        return size

    def read_bytes(self, trip_id: str, filename: str) -> bytes:
        target = self._target(trip_id, filename)
        if not target.is_file():
            raise FileNotFoundError("Media object not found")
        return target.read_bytes()

    def local_path(self, trip_id: str, filename: str) -> Path | None:
        target = self._target(trip_id, filename)
        return target if target.is_file() else None

    def delete(self, trip_id: str, filename: str) -> bool:
        target = self._target(trip_id, filename)
        if not target.is_file():
            return False
        target.unlink()
        return True

    def stats(self) -> MediaStorageStats:
        total_files = 0
        total_bytes = 0
        if self.root.exists():
            for item in self.root.rglob("*"):
                if item.is_file():
                    total_files += 1
                    total_bytes += item.stat().st_size
        return MediaStorageStats(
            backend=self.backend_name,
            storage_dir=self.root.name,
            total_files=total_files,
            total_bytes=total_bytes,
        )


class InMemoryMediaStore:
    """Non-persistent backend used by tests and local verification."""

    backend_name = "memory"

    def __init__(self) -> None:
        self._objects: dict[MediaKey, bytes] = {}

    def ensure_ready(self) -> None:
        return None

    async def save(
        self,
        trip_id: str,
        filename: str,
        chunks: AsyncIterator[bytes],
        max_bytes: int,
    ) -> int:
        key = parse_media_key(trip_id, filename)
        if key in self._objects:
            raise MediaValidationError("Media object already exists")
        payload = bytearray()
        async for chunk in chunks:
            if len(payload) + len(chunk) > max_bytes:
                raise MediaTooLargeError("Media object is too large")
            payload.extend(chunk)
        self._objects[key] = bytes(payload)
        return len(payload)

    def read_bytes(self, trip_id: str, filename: str) -> bytes:
        key = parse_media_key(trip_id, filename)
        if key not in self._objects:
            raise FileNotFoundError("Media object not found")
        return self._objects[key]

    def local_path(self, trip_id: str, filename: str) -> Path | None:
        return None

    def delete(self, trip_id: str, filename: str) -> bool:
        key = parse_media_key(trip_id, filename)
        return self._objects.pop(key, None) is not None

    def stats(self) -> MediaStorageStats:
        return MediaStorageStats(
            backend=self.backend_name,
            storage_dir=None,
            total_files=len(self._objects),
            total_bytes=sum(len(value) for value in self._objects.values()),
        )


_store: MediaStore | None = None


def build_media_store(backend: str, root: Path) -> MediaStore:
    """Create a store. Unsupported backends fail closed at startup."""
    if backend == "local":
        return LocalMediaStore(root)
    if backend == "memory":
        return InMemoryMediaStore()
    raise RuntimeError(
        f"SAFAR_MEDIA_BACKEND={backend!r} is not implemented; use 'local' or 'memory'."
    )


def get_media_store() -> MediaStore:
    global _store
    if _store is None:
        _store = build_media_store(settings.media_backend, settings.storage_dir)
    return _store


def set_media_store(store: MediaStore | None) -> None:
    """Replace the process-wide store. Intended for isolated tests."""
    global _store
    _store = store
