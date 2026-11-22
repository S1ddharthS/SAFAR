"""Optional page-metadata reader for Dream Import links.

Disabled by default. When enabled, only the page's own title/description are
read, through the SSRF-guarded client, and the result is labelled as reported
by the site rather than verified by SAFAR.
"""

from datetime import datetime
from html.parser import HTMLParser

from app.core.config import settings
from app.integrations import base, http
from app.integrations.base import ProviderResult
from app.integrations.cache import TTLCache
from app.integrations.ratelimit import TokenBucket

PROVIDER = "page-metadata"
_MAX_FIELD = 400

_cache = TTLCache(max_entries=256)
_bucket = TokenBucket(settings.link_rate_limit_per_minute, burst=5)

_META_KEYS = {
    "og:title",
    "og:description",
    "og:site_name",
    "twitter:title",
    "twitter:description",
    "description",
}


def reset() -> None:
    _cache.clear()
    _bucket.reset()


def status() -> dict:
    return {
        "provider": PROVIDER,
        "enabled": settings.link_fetch_enabled,
        "network": True,
        "provenance": base.REPORTED,
        "notes": (
            ["Reads only the page's own metadata, never the article body."]
            if settings.link_fetch_enabled
            else ["Disabled. Only the URL string supplied by the traveller is inspected."]
        ),
    }


class _MetadataParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.lang: str | None = None
        self.title_parts: list[str] = []
        self._in_title = False
        self.meta: dict[str, str] = {}

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = {key.lower(): (value or "") for key, value in attrs}
        if tag == "html" and values.get("lang"):
            self.lang = values["lang"][:20]
        elif tag == "title":
            self._in_title = True
        elif tag == "meta":
            key = (values.get("property") or values.get("name") or "").strip().lower()
            content = values.get("content", "").strip()
            if key in _META_KEYS and content and key not in self.meta:
                self.meta[key] = content

    def handle_endtag(self, tag: str) -> None:
        if tag == "title":
            self._in_title = False

    def handle_data(self, data: str) -> None:
        if self._in_title:
            self.title_parts.append(data)


def _clean(value: str | None) -> str | None:
    if not value:
        return None
    text = " ".join(value.split())
    return text[:_MAX_FIELD] or None


def parse_metadata(html: str) -> dict:
    parser = _MetadataParser()
    parser.feed(html)
    title = _clean(" ".join(parser.title_parts)) or _clean(parser.meta.get("og:title"))
    description = (
        _clean(parser.meta.get("og:description"))
        or _clean(parser.meta.get("twitter:description"))
        or _clean(parser.meta.get("description"))
    )
    return {
        "title": title or _clean(parser.meta.get("twitter:title")),
        "description": description,
        "site_name": _clean(parser.meta.get("og:site_name")),
        "lang": parser.lang,
    }


def fetch_metadata(url: str) -> ProviderResult:
    if not settings.link_fetch_enabled:
        return base.unavailable(
            PROVIDER,
            "Link reading is disabled on this deployment. Only the URL string was inspected.",
        )
    cached = _cache.get(f"link:{url}")
    if cached:
        value, _ = cached
        fetched_at = value.get("fetched_at")
        return ProviderResult(
            ok=True,
            provider=PROVIDER,
            data=value["data"],
            provenance=base.REPORTED,
            fetched_at=datetime.fromisoformat(fetched_at) if fetched_at else None,
            cached=True,
            message="Read from the page's own metadata, cached from an earlier read.",
        )
    if not _bucket.allow():
        return base.failed(
            PROVIDER, "rate_limited", "Too many link reads right now. Try again in a minute."
        )
    try:
        response = http.fetch_text(
            url,
            timeout=settings.provider_timeout_seconds,
            max_bytes=262144,
        )
    except http.FetchError as exc:
        return base.failed(PROVIDER, exc.code, exc.message)
    if "html" not in response.content_type.lower():
        return base.failed(
            PROVIDER, "unsupported_content", "That link is not an HTML page, so nothing was read."
        )
    data = parse_metadata(response.text)
    if not data["title"] and not data["description"]:
        return base.failed(
            PROVIDER,
            "no_metadata",
            "The page was reached but did not expose a title or description.",
        )
    data["source_url"] = url
    fetched_at = base.now()
    _cache.set(
        f"link:{url}",
        {"data": data, "fetched_at": fetched_at.isoformat()},
        settings.link_cache_ttl_seconds,
    )
    return ProviderResult(
        ok=True,
        provider=PROVIDER,
        data=data,
        provenance=base.REPORTED,
        fetched_at=fetched_at,
        message=(
            "Read from the page's own metadata. It is reported by the site, "
            "not verified by SAFAR."
        ),
    )
