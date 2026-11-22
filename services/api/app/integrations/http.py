"""Bounded HTTP client with SSRF protection.

Only public http(s) URLs on ports 80/443 are fetched. Every resolved address is
checked before connecting, redirects are never followed, responses are size
capped and requests time out. Proxy environment variables are ignored so a
misconfigured deployment cannot silently reroute fetches.
"""

import ipaddress
import json
import socket
from dataclasses import dataclass
from typing import Any
from urllib.parse import urlsplit

import httpx

USER_AGENT = "SAFAR-LinkReader/1.0 (+https://safar.local; metadata only)"
ALLOWED_PORTS = {80, 443}
_BLOCKED_NETWORKS = [
    ipaddress.ip_network("0.0.0.0/8"),
    ipaddress.ip_network("100.64.0.0/10"),
    ipaddress.ip_network("192.0.0.0/24"),
    ipaddress.ip_network("198.18.0.0/15"),
]
_BLOCKED_HOST_SUFFIXES = (".localhost", ".local", ".internal", ".home.arpa")


class FetchError(Exception):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


@dataclass(slots=True)
class TextResponse:
    status_code: int
    content_type: str
    text: str


def _ip_is_public(value: str) -> bool:
    try:
        address = ipaddress.ip_address(value)
    except ValueError:
        return False
    if any(address in network for network in _BLOCKED_NETWORKS):
        return False
    return not (
        address.is_private
        or address.is_loopback
        or address.is_link_local
        or address.is_reserved
        or address.is_multicast
        or address.is_unspecified
    )


def assert_public_url(url: str) -> str:
    """Validate scheme, port, host and resolved addresses. Returns the URL."""
    parts = urlsplit(url.strip())
    if parts.scheme not in {"http", "https"}:
        raise FetchError("unsupported_scheme", "Only http and https links can be read.")
    if parts.username or parts.password:
        raise FetchError("credentials_in_url", "Links with embedded credentials are not fetched.")
    host = (parts.hostname or "").rstrip(".").lower()
    if not host:
        raise FetchError("invalid_url", "That link does not contain a hostname.")
    try:
        port = parts.port or (443 if parts.scheme == "https" else 80)
    except ValueError as exc:
        raise FetchError("invalid_port", "That link has an invalid port.") from exc
    if port not in ALLOWED_PORTS:
        raise FetchError("unsupported_port", "Only standard web ports are supported.")
    if host == "localhost" or host.endswith(_BLOCKED_HOST_SUFFIXES):
        raise FetchError("private_address", "Links to private network hosts are not fetched.")

    try:
        literal = ipaddress.ip_address(host)
    except ValueError:
        literal = None
    if literal is not None:
        if not _ip_is_public(str(literal)):
            raise FetchError("private_address", "Links to private network addresses are not fetched.")
        return url

    try:
        resolved = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
    except OSError as exc:
        raise FetchError("unresolvable_host", "That link's hostname could not be resolved.") from exc
    if not resolved:
        raise FetchError("unresolvable_host", "That link's hostname could not be resolved.")
    for info in resolved:
        if not _ip_is_public(info[4][0]):
            raise FetchError("private_address", "Links resolving to private addresses are not fetched.")
    return url


def _client(timeout: float) -> httpx.Client:
    return httpx.Client(
        timeout=httpx.Timeout(timeout, connect=min(2.0, timeout)),
        follow_redirects=False,
        trust_env=False,
        headers={"User-Agent": USER_AGENT, "Accept-Encoding": "identity"},
    )


def fetch_text(
    url: str,
    *,
    timeout: float = 3.0,
    max_bytes: int = 262144,
    accept: str = "text/html,application/xhtml+xml",
) -> TextResponse:
    assert_public_url(url)
    try:
        with _client(timeout) as client:
            with client.stream("GET", url, headers={"Accept": accept}) as response:
                if response.is_redirect:
                    raise FetchError(
                        "redirect_not_followed",
                        "That link redirects elsewhere, so it was not read.",
                    )
                if response.status_code >= 400:
                    raise FetchError(
                        f"http_{response.status_code}",
                        f"The linked page returned status {response.status_code}.",
                    )
                declared = response.headers.get("content-length")
                if declared and declared.isdigit() and int(declared) > max_bytes:
                    raise FetchError("response_too_large", "That page is too large to read safely.")
                body = bytearray()
                for chunk in response.iter_bytes():
                    body.extend(chunk)
                    if len(body) > max_bytes:
                        raise FetchError("response_too_large", "That page is too large to read safely.")
                encoding = response.encoding or "utf-8"
                return TextResponse(
                    status_code=response.status_code,
                    content_type=response.headers.get("content-type", ""),
                    text=body.decode(encoding, errors="replace"),
                )
    except FetchError:
        raise
    except httpx.TimeoutException as exc:
        raise FetchError("timeout", "That link did not respond in time.") from exc
    except httpx.HTTPError as exc:
        raise FetchError("request_failed", "That link could not be reached.") from exc


def fetch_json(url: str, *, timeout: float = 3.0, max_bytes: int = 262144) -> dict[str, Any]:
    response = fetch_text(
        url, timeout=timeout, max_bytes=max_bytes, accept="application/json"
    )
    try:
        payload = json.loads(response.text)
    except json.JSONDecodeError as exc:
        raise FetchError("invalid_response", "The provider returned data that could not be read.") from exc
    if not isinstance(payload, dict):
        raise FetchError("invalid_response", "The provider returned an unexpected shape.")
    return payload
