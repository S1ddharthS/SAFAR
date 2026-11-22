"""Signed media URLs.

Trip media is private by default. Files are only served with a short-lived
HMAC signature that is issued to authenticated trip members through API
responses. The previous unauthenticated StaticFiles mount let anyone with a
URL read private photos, including memories marked private.
"""

import hashlib
import hmac
import time
from urllib.parse import urlsplit, urlunsplit

from app.core.config import settings

MEDIA_TTL_SECONDS = 12 * 60 * 60


def _signature(path: str, expires: int) -> str:
    message = f"{path}:{expires}".encode("utf-8")
    return hmac.new(
        settings.secret_key.encode("utf-8"), message, hashlib.sha256
    ).hexdigest()


def canonical_media_url(url: str | None) -> str | None:
    """Strip any signature so only the stored path is persisted."""
    if not url or not url.startswith("/media/"):
        return url
    parts = urlsplit(url)
    return urlunsplit((parts.scheme, parts.netloc, parts.path, "", ""))


def sign_media_url(url: str | None, ttl: int = MEDIA_TTL_SECONDS) -> str | None:
    if not url or not url.startswith("/media/"):
        return url
    path = canonical_media_url(url)
    assert path is not None
    expires = int(time.time()) + ttl
    separator = "&" if "?" in path else "?"
    return f"{path}{separator}exp={expires}&sig={_signature(path, expires)}"


def verify_media_request(path: str, query: dict[str, str]) -> bool:
    try:
        expires = int(query.get("exp", "0"))
    except ValueError:
        return False
    signature = query.get("sig", "")
    if not signature or expires < int(time.time()):
        return False
    return hmac.compare_digest(signature, _signature(path, expires))


def media_matches_type(content_type: str, head: bytes) -> bool:
    """Check the file signature instead of trusting the client's MIME type."""
    if content_type == "image/jpeg":
        return head[:3] == b"\xff\xd8\xff"
    if content_type == "image/png":
        return head[:8] == b"\x89PNG\r\n\x1a\n"
    if content_type == "image/webp":
        return head[:4] == b"RIFF" and head[8:12] == b"WEBP"
    if content_type == "video/mp4":
        return head[4:8] == b"ftyp"
    if content_type == "audio/webm":
        return head[:4] == b"\x1aE\xdf\xa3"
    if content_type == "audio/mpeg":
        return head[:3] == b"ID3" or (len(head) >= 2 and head[0] == 0xFF and head[1] & 0xE0 == 0xE0)
    if content_type == "audio/ogg":
        return head[:4] == b"OggS"
    if content_type == "audio/wav":
        return head[:4] == b"RIFF" and head[8:12] == b"WAVE"
    return False
