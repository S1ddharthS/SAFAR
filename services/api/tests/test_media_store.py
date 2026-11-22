"""Coverage for the private media storage adapter seam."""

import asyncio
from pathlib import Path

import pytest
from urllib.parse import urlsplit

from app.services.media import sign_media_url
from app.services.media_store import (
    InMemoryMediaStore,
    LocalMediaStore,
    MediaTooLargeError,
    MediaValidationError,
    build_media_store,
    parse_media_key,
    parse_media_url,
)

TRIP_ID = "a" * 32
OTHER_TRIP_ID = "b" * 32


async def _chunks(parts):
    for part in parts:
        yield part


def test_local_store_saves_reads_and_deletes_within_trip_scope(tmp_path):
    store = LocalMediaStore(tmp_path / "media")
    store.ensure_ready()

    size = asyncio.run(store.save(TRIP_ID, "photo.jpg", _chunks([b"ab", b"cd"]), 100))

    assert size == 4
    assert store.read_bytes(TRIP_ID, "photo.jpg") == b"abcd"
    path = store.local_path(TRIP_ID, "photo.jpg")
    assert path is not None and path.is_file()
    assert path.parent.name == TRIP_ID
    assert store.stats().total_files == 1
    assert store.delete(TRIP_ID, "photo.jpg") is True
    assert store.delete(TRIP_ID, "photo.jpg") is False


def test_local_store_rejects_traversal_and_cross_trip_keys(tmp_path):
    store = LocalMediaStore(tmp_path / "media")
    store.ensure_ready()

    for trip_id, filename in [
        ("../" + TRIP_ID, "photo.jpg"),
        (TRIP_ID, ".."),
        (TRIP_ID, "../photo.jpg"),
        (TRIP_ID, "nested/photo.jpg"),
        ("not-a-trip-id", "photo.jpg"),
    ]:
        with pytest.raises(MediaValidationError):
            parse_media_key(trip_id, filename)
        with pytest.raises(MediaValidationError):
            store.local_path(trip_id, filename)


def test_local_store_enforces_size_limit_without_leaving_partial_files(tmp_path):
    store = LocalMediaStore(tmp_path / "media")
    store.ensure_ready()

    with pytest.raises(MediaTooLargeError):
        asyncio.run(store.save(TRIP_ID, "large.jpg", _chunks([b"x" * 11]), 10))

    assert list((tmp_path / "media" / TRIP_ID).iterdir()) == []


def test_media_url_parsing_ignores_signature_but_enforces_trip_scope():
    signed = sign_media_url(f"/media/{TRIP_ID}/photo.jpg")
    assert signed is not None

    key = parse_media_url(signed, expected_trip_id=TRIP_ID)
    assert key.trip_id == TRIP_ID
    assert key.filename == "photo.jpg"
    assert urlsplit(signed).query.startswith("exp=")

    with pytest.raises(MediaValidationError):
        parse_media_url(signed, expected_trip_id=OTHER_TRIP_ID)
    with pytest.raises(MediaValidationError):
        parse_media_url("https://example.com/media/photo.jpg")
    with pytest.raises(MediaValidationError):
        parse_media_url(f"/media/{TRIP_ID}/../photo.jpg")


def test_memory_store_has_no_filesystem_path():
    store = InMemoryMediaStore()
    size = asyncio.run(store.save(TRIP_ID, "photo.png", _chunks([b"png"]), 100))

    assert size == 3
    assert store.read_bytes(TRIP_ID, "photo.png") == b"png"
    assert store.local_path(TRIP_ID, "photo.png") is None
    assert store.stats().backend == "memory"
    assert store.stats().total_bytes == 3
    assert store.delete(TRIP_ID, "photo.png") is True


def test_unknown_backend_fails_closed():
    with pytest.raises(RuntimeError):
        build_media_store("cloud", Path("/unused"))


def test_upload_writes_through_the_configured_adapter(client, mira, kyoto, monkeypatch):
    from app.services import media_store as media_store_module

    memory_store = InMemoryMediaStore()
    monkeypatch.setattr(media_store_module, "_store", memory_store)

    response = client.post(
        f"/api/trips/{kyoto['id']}/media",
        headers=mira,
        files={"file": ("probe.png", b"\x89PNG\r\n\x1a\nprobe", "image/png")},
    )
    assert response.status_code == 201, response.text

    signed_url = response.json()["media_url"]
    key = parse_media_url(signed_url, expected_trip_id=kyoto["id"])
    assert memory_store.read_bytes(key.trip_id, key.filename).startswith(b"\x89PNG")
