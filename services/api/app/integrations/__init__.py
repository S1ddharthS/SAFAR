"""Optional external providers.

Every adapter returns a :class:`ProviderResult` and degrades instead of
raising. Nothing in this package is enabled by default except local, free
capabilities (in-repo language templates and local OCR when the binary exists).
"""

from app.integrations.base import (  # noqa: F401
    ESTIMATED,
    PREDICTED,
    REPORTED,
    UNKNOWN,
    VERIFIED,
    ProviderResult,
    failed,
    unavailable,
)
