"""Small in-process TTL cache for provider responses.

Provider data is public catalog/weather/page data; caching keeps repeated
assistant turns from re-hitting a provider and keeps latency predictable.
"""

import copy
import time
from threading import Lock
from typing import Any


class TTLCache:
    def __init__(self, max_entries: int = 512) -> None:
        self.max_entries = max_entries
        self._rows: dict[str, tuple[float, Any]] = {}
        self._lock = Lock()

    def get(self, key: str) -> tuple[Any, bool] | None:
        with self._lock:
            row = self._rows.get(key)
            if not row:
                return None
            expires_at, value = row
            if expires_at < time.monotonic():
                self._rows.pop(key, None)
                return None
            return copy.deepcopy(value), False

    def set(self, key: str, value: Any, ttl_seconds: float) -> None:
        if ttl_seconds <= 0:
            return
        with self._lock:
            if len(self._rows) >= self.max_entries and key not in self._rows:
                oldest = min(self._rows, key=lambda item: self._rows[item][0])
                self._rows.pop(oldest, None)
            self._rows[key] = (time.monotonic() + ttl_seconds, copy.deepcopy(value))

    def clear(self) -> None:
        with self._lock:
            self._rows.clear()

    def __len__(self) -> int:
        with self._lock:
            return len(self._rows)
