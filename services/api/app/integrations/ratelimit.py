"""Per-provider token bucket.

Weather is cached for 30 minutes and links for 15, so these buckets rarely
trigger. They exist to bound a misbehaving caller, not to throttle normal use.
"""

import time
from threading import Lock


class TokenBucket:
    def __init__(self, rate_per_minute: int, burst: int | None = None) -> None:
        self.rate = max(1, rate_per_minute) / 60.0
        self.capacity = float(burst if burst is not None else max(1, rate_per_minute))
        self._tokens = self.capacity
        self._updated = time.monotonic()
        self._lock = Lock()

    def allow(self, tokens: float = 1.0) -> bool:
        with self._lock:
            current = time.monotonic()
            elapsed = current - self._updated
            self._tokens = min(self.capacity, self._tokens + elapsed * self.rate)
            self._updated = current
            if self._tokens < tokens:
                return False
            self._tokens -= tokens
            return True

    def reset(self) -> None:
        with self._lock:
            self._tokens = self.capacity
            self._updated = time.monotonic()
