"""Provider result envelope and provenance constants.

Callers must never treat a provider value as verified fact. ``provenance``
travels with the data all the way to the response so the UI can label it.
"""

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

VERIFIED = "VERIFIED"
REPORTED = "REPORTED"
ESTIMATED = "ESTIMATED"
PREDICTED = "PREDICTED"
UNKNOWN = "UNKNOWN"


@dataclass(slots=True)
class ProviderResult:
    ok: bool
    provider: str
    data: dict[str, Any] | None = None
    provenance: str = UNKNOWN
    fetched_at: datetime | None = None
    cached: bool = False
    error: str | None = None
    message: str | None = None
    attribution: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "ok": self.ok,
            "provider": self.provider,
            "data": self.data,
            "provenance": self.provenance,
            "fetched_at": self.fetched_at.isoformat() if self.fetched_at else None,
            "cached": self.cached,
            "error": self.error,
            "message": self.message,
            "attribution": self.attribution,
        }


def now() -> datetime:
    return datetime.now(timezone.utc)


def unavailable(provider: str, message: str, error: str = "unavailable") -> ProviderResult:
    """The provider is not configured or not installed. Not an error state."""
    return ProviderResult(ok=False, provider=provider, error=error, message=message)


def failed(provider: str, error: str, message: str) -> ProviderResult:
    """The provider was tried and did not deliver usable data."""
    return ProviderResult(ok=False, provider=provider, error=error, message=message)
