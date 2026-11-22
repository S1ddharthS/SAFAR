"""Phase 7 F17 evaluation: Dream Import extraction, provenance and review.

These tests exercise the real endpoints and the real extraction service. They
assert the properties the feature promises: candidates are estimates that keep
their source and span, nothing is auto-confirmed, providers that are off say so
honestly, and review decisions are recorded.
"""

import base64

import pytest

from app.integrations import http

# 1x1 transparent PNG, enough to exercise the real upload + OCR adapter path.
_PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
)


def _import(client, headers, trip_id, **payload):
    response = client.post(
        f"/api/trips/{trip_id}/inspirations", headers=headers, json=payload
    )
    assert response.status_code == 201, response.text
    return response.json()


def _review(client, headers, trip_id, inspiration_id, candidate_id, decision):
    return client.post(
        f"/api/trips/{trip_id}/inspirations/{inspiration_id}/review",
        headers=headers,
        json={"candidate_id": candidate_id, "decision": decision},
    )


def test_text_extraction_keeps_provenance_and_source_spans(client, mira, kyoto):
    body = _import(
        client,
        mira,
        kyoto["id"],
        source_type="text",
        content=(
            "Kyoto in April, Fushimi Inari Torii Walk with #temple focus, "
            "budget under €450, 6 days, 12-18 April 2027. "
            "If not, we could go in November."
        ),
    )
    extraction = body["extraction"]
    assert body["status"] == "extracted"
    assert extraction["status"] == "needs_confirmation"
    assert "suggestion" in body["disclosure"].lower()
    matches = extraction["matches"]
    assert matches

    for match in matches:
        assert match["provenance"] == "ESTIMATED"
        assert match["verified"] is False
        assert match["decision"] == "pending"
        assert match["candidate_id"].startswith(f"{match['type']}:")
        assert match["source"] in {"text", "link_metadata", "ocr", "url_path"}
        if match["source"] in {"text", "link_metadata", "ocr"}:
            assert match["source_span"] is not None
            span = match["source_span"]
            assert 0 <= span["start"] < span["end"]

    by_type = {}
    for match in matches:
        by_type.setdefault(match["type"], []).append(match)

    assert "destination" in by_type
    assert by_type["destination"][0]["name"] == "Kyoto"
    assert by_type["destination"][0]["source"] == "text"
    assert by_type["destination"][0]["source_span"]["text"].strip() == "Kyoto"

    assert any(match["name"] == "Fushimi Inari Torii Walk" for match in by_type["activity"])
    assert any("450" in match["name"] for match in by_type["budget_hint"])
    dates = [match["name"] for match in by_type["travel_dates"]]
    assert "12-18 April 2027" in dates
    assert any(match["name"] == "November" for match in by_type["travel_window"])
    durations = [match for match in by_type["trip_length"]]
    assert durations and durations[0]["value"] == {"amount": 6, "unit": "days"}

    assert "temple" in extraction["metadata"]["hashtags"]
    assert any(source["kind"] == "text" for source in extraction["metadata"]["sources"])
    assert extraction["review"] == {
        "pending": len(matches),
        "accepted": 0,
        "rejected": 0,
    }
    assert any("not verified facts" in note for note in extraction["limitations"])


def test_review_accept_and_reject_updates_counts_and_status(client, mira, kyoto):
    body = _import(
        client,
        mira,
        kyoto["id"],
        source_type="text",
        content="Kyoto in May, Fushimi Inari Torii Walk, budget around $300.",
    )
    inspiration_id = body["id"]
    matches = body["extraction"]["matches"]
    assert len(matches) >= 2
    candidate_ids = [match["candidate_id"] for match in matches]

    accepted = _review(client, mira, kyoto["id"], inspiration_id, candidate_ids[0], "accept")
    assert accepted.status_code == 200, accepted.text
    accepted_body = accepted.json()
    assert accepted_body["status"] == "extracted"
    assert accepted_body["extraction"]["review"]["accepted"] == 1
    assert accepted_body["extraction"]["review"]["pending"] == len(candidate_ids) - 1
    decision = accepted_body["extraction"]["decisions"][candidate_ids[0]]
    assert decision["decision"] == "accept"
    assert decision["decided_at"]
    match = next(
        item for item in accepted_body["extraction"]["matches"]
        if item["candidate_id"] == candidate_ids[0]
    )
    assert match["decision"] == "accept"
    assert "proposal" in accepted_body["disclosure"].lower()

    latest = accepted_body
    for candidate_id in candidate_ids[1:]:
        response = _review(client, mira, kyoto["id"], inspiration_id, candidate_id, "reject")
        assert response.status_code == 200, response.text
        latest = response.json()
    review = latest["extraction"]["review"]
    assert review == {"pending": 0, "accepted": 1, "rejected": len(candidate_ids) - 1}
    assert latest["status"] == "reviewed"

    unknown = _review(client, mira, kyoto["id"], inspiration_id, "activity:not-a-candidate", "accept")
    assert unknown.status_code == 404


def test_review_rejecting_every_candidate_marks_inspiration_rejected(client, mira, kyoto):
    body = _import(
        client,
        mira,
        kyoto["id"],
        source_type="text",
        content="A slow tea morning in Kyoto.",
    )
    latest = body
    for match in body["extraction"]["matches"]:
        response = _review(
            client, mira, kyoto["id"], body["id"], match["candidate_id"], "reject"
        )
        assert response.status_code == 200, response.text
        latest = response.json()
    assert latest["status"] == "rejected"
    assert latest["extraction"]["review"]["accepted"] == 0
    assert latest["extraction"]["review"]["pending"] == 0


def test_link_import_is_honest_when_page_fetching_is_disabled(client, mira, kyoto):
    body = _import(
        client,
        mira,
        kyoto["id"],
        source_type="link",
        content="https://www.kyoto.travel/en/tea-ceremony",
    )
    extraction = body["extraction"]
    assert any("kyoto.travel" in host for host in extraction["metadata"]["source_hosts"])
    provider = extraction["metadata"]["providers"][0]
    assert provider["provider"] == "page-metadata"
    assert provider["ok"] is False
    assert any(
        "Link not read" in note and "disabled" in note
        for note in extraction["limitations"]
    )
    assert any(
        match["source"] == "url_path" and match["type"] == "destination"
        for match in extraction["matches"]
    )


def test_link_without_url_reports_missing_address(client, mira, kyoto):
    body = _import(
        client,
        mira,
        kyoto["id"],
        source_type="link",
        content="A saved article about temple gardens",
    )
    limitations = body["extraction"]["limitations"]
    assert any(
        "Link not read" in note and "No web address" in note for note in limitations
    )
    assert body["extraction"]["metadata"]["providers"][0]["ok"] is False


def test_text_import_with_url_never_fetches_the_page(client, mira, kyoto):
    body = _import(
        client,
        mira,
        kyoto["id"],
        source_type="text",
        content="Saw this: https://www.kyoto.travel/en/gardens — worth a morning.",
    )
    extraction = body["extraction"]
    assert extraction["metadata"]["providers"] == []
    assert extraction["metadata"]["urls"]
    assert any("kyoto.travel" in host for host in extraction["metadata"]["source_hosts"])


def test_image_import_uses_local_media_and_labels_ocr(client, mira, kyoto):
    upload = client.post(
        f"/api/trips/{kyoto['id']}/media",
        headers=mira,
        files={"file": ("screenshot.png", _PNG, "image/png")},
    )
    assert upload.status_code == 201, upload.text
    media_url = upload.json()["media_url"]
    assert media_url.startswith(f"/media/{kyoto['id']}/")

    body = _import(
        client,
        mira,
        kyoto["id"],
        source_type="image_url",
        content="",
        media_url=media_url,
    )
    extraction = body["extraction"]
    assert body["status"] == "extracted"
    assert extraction["metadata"]["ocr"] is not None
    ocr = extraction["metadata"]["ocr"]
    if ocr["available"]:
        assert any("machine-read" in note for note in extraction["notes"])
    else:
        assert any("OCR was not available" in note for note in extraction["limitations"])
    # The adapter is local-only: no image leaves this server.
    from app.integrations import ocr as ocr_provider

    assert ocr_provider.status()["network"] is False
    assert any("never uploaded" in note for note in ocr_provider.status()["notes"])


def test_image_import_without_media_asks_for_the_image(client, mira, kyoto):
    response = client.post(
        f"/api/trips/{kyoto['id']}/inspirations",
        headers=mira,
        json={"source_type": "image_url", "content": ""},
    )
    assert response.status_code == 422
    assert "image" in response.json()["detail"].lower()


def test_media_url_must_be_a_signed_local_upload(client, mira, kyoto):
    external = client.post(
        f"/api/trips/{kyoto['id']}/inspirations",
        headers=mira,
        json={
            "source_type": "image_url",
            "content": "Screenshot",
            "media_url": "https://example.com/private.png",
        },
    )
    assert external.status_code == 422
    assert "local" in external.json()["detail"].lower()

    other_trip = client.post(
        f"/api/trips/{kyoto['id']}/inspirations",
        headers=mira,
        json={
            "source_type": "image_url",
            "content": "Screenshot",
            "media_url": f"/media/another-trip/photo.png?exp=9999999999&sig=abc",
        },
    )
    assert other_trip.status_code == 422
    assert "belong" in other_trip.json()["detail"].lower()

    traversal = client.post(
        f"/api/trips/{kyoto['id']}/inspirations",
        headers=mira,
        json={
            "source_type": "image_url",
            "content": "Screenshot",
            "media_url": f"/media/{kyoto['id']}/../secret.png",
        },
    )
    assert traversal.status_code == 422
    assert "Invalid media name" in traversal.json()["detail"]

    unsigned = client.post(
        f"/api/trips/{kyoto['id']}/inspirations",
        headers=mira,
        json={
            "source_type": "image_url",
            "content": "Screenshot",
            "media_url": f"/media/{kyoto['id']}/photo.png",
        },
    )
    assert unsigned.status_code == 403


def test_link_reader_blocks_private_addresses():
    with pytest.raises(http.FetchError) as loopback:
        http.assert_public_url("http://127.0.0.1/")
    assert loopback.value.code == "private_address"

    with pytest.raises(http.FetchError) as port:
        http.assert_public_url("http://example.com:8080/")
    assert port.value.code == "unsupported_port"

    with pytest.raises(http.FetchError) as scheme:
        http.assert_public_url("ftp://example.com/file")
    assert scheme.value.code == "unsupported_scheme"

    assert http.assert_public_url("https://example.com/article") == "https://example.com/article"
