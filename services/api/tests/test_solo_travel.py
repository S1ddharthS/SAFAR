from datetime import date, timedelta
import pytest
from fastapi.testclient import TestClient


def test_create_solo_trip(client: TestClient, mira: dict[str, str]):
    start = date.today() + timedelta(days=10)
    end = start + timedelta(days=5)

    payload = {
        "name": "Kyoto Solo Wander",
        "description": "Solo journey exploring temples and tea houses",
        "destination_name": "Kyoto, Japan",
        "start_date": start.isoformat(),
        "end_date": end.isoformat(),
        "group_size": 1,
        "trip_type": "solo",
        "budget_total": 1200.0,
        "currency": "EUR",
    }
    resp = client.post("/api/trips", json=payload, headers=mira)
    assert resp.status_code == 201, resp.text
    data = resp.json()
    assert data["name"] == "Kyoto Solo Wander"
    assert data["trip_type"] == "solo"
    assert data["group_size"] == 1
    trip_id = data["id"]

    # Verify get_trip returns trip_type
    get_resp = client.get(f"/api/trips/{trip_id}", headers=mira)
    assert get_resp.status_code == 200
    assert get_resp.json()["trip_type"] == "solo"

    # Verify Solo Safety Centre status
    safety_resp = client.get(f"/api/trips/{trip_id}/safety", headers=mira)
    assert safety_resp.status_code == 200, safety_resp.text
    safety_data = safety_resp.json()
    assert safety_data["is_solo"] is True
    assert safety_data["trip_id"] == trip_id
    assert safety_data["local_emergency_numbers"]["country_code"] == "JP"
    assert safety_data["local_emergency_numbers"]["police"] == "110"
    assert safety_data["local_emergency_numbers"]["ambulance"] == "119"
    assert safety_data["settings"]["check_in_frequency_hours"] == 24


def test_solo_safety_emergency_contacts(client: TestClient, mira: dict[str, str]):
    start = date.today() + timedelta(days=20)
    end = start + timedelta(days=4)

    trip_resp = client.post(
        "/api/trips",
        json={
            "name": "Tokyo Solo Walk",
            "start_date": start.isoformat(),
            "end_date": end.isoformat(),
            "group_size": 1,
            "trip_type": "solo",
        },
        headers=mira,
    )
    trip_id = trip_resp.json()["id"]

    # Add primary emergency contact
    contact_payload = {
        "name": "Elena Vance",
        "relationship": "Sister",
        "phone": "+15551234567",
        "email": "elena@example.com",
        "notes": "Available evenings UTC",
        "is_primary": True,
    }
    create_contact_resp = client.post(
        f"/api/trips/{trip_id}/safety/contacts",
        json=contact_payload,
        headers=mira,
    )
    assert create_contact_resp.status_code == 201, create_contact_resp.text
    contact = create_contact_resp.json()
    contact_id = contact["id"]
    assert contact["name"] == "Elena Vance"
    assert contact["relationship"] == "Sister"
    assert contact["is_primary"] is True

    # Check status includes the contact
    safety_resp = client.get(f"/api/trips/{trip_id}/safety", headers=mira)
    contacts = safety_resp.json()["contacts"]
    assert len(contacts) == 1
    assert contacts[0]["id"] == contact_id

    # Delete contact
    del_resp = client.delete(f"/api/trips/{trip_id}/safety/contacts/{contact_id}", headers=mira)
    assert del_resp.status_code == 204

    # Verify deleted
    safety_resp2 = client.get(f"/api/trips/{trip_id}/safety", headers=mira)
    assert len(safety_resp2.json()["contacts"]) == 0


def test_solo_check_in_and_safety_beacon(client: TestClient, mira: dict[str, str]):
    start = date.today() + timedelta(days=15)
    end = start + timedelta(days=3)

    trip_resp = client.post(
        "/api/trips",
        json={
            "name": "London Solo Escape",
            "destination_name": "London, United Kingdom",
            "start_date": start.isoformat(),
            "end_date": end.isoformat(),
            "group_size": 1,
            "trip_type": "solo",
        },
        headers=mira,
    )
    trip_id = trip_resp.json()["id"]

    # Record check-in
    check_in_resp = client.post(
        f"/api/trips/{trip_id}/safety/check-in",
        json={
            "status": "safe",
            "location_name": "Covent Garden Market",
            "lat": 51.5117,
            "lon": -0.1240,
            "message": "Checked into hotel, heading for coffee.",
        },
        headers=mira,
    )
    assert check_in_resp.status_code == 201, check_in_resp.text
    ci_data = check_in_resp.json()
    assert ci_data["status"] == "safe"
    assert ci_data["location_name"] == "Covent Garden Market"

    # Update settings: enable location sharing and set 12-hour check-in
    patch_settings_resp = client.patch(
        f"/api/trips/{trip_id}/safety/settings",
        json={"check_in_frequency_hours": 12, "location_sharing_enabled": True},
        headers=mira,
    )
    assert patch_settings_resp.status_code == 200
    settings_data = patch_settings_resp.json()
    assert settings_data["check_in_frequency_hours"] == 12
    assert settings_data["location_sharing_enabled"] is True
    share_token = settings_data["share_token"]
    assert share_token is not None and len(share_token) > 10

    # Public beacon check (unauthenticated)
    beacon_resp = client.get(f"/api/safety/beacon/{share_token}")
    assert beacon_resp.status_code == 200, beacon_resp.text
    beacon = beacon_resp.json()
    assert beacon["trip_name"] == "London Solo Escape"
    assert beacon["destination_name"] == "London, United Kingdom"
    assert beacon["status"] == "safe"
    assert beacon["last_location_name"] == "Covent Garden Market"
    assert beacon["is_overdue"] is False

    # Invalid token check returns 404
    bad_beacon_resp = client.get("/api/safety/beacon/invalid-nonexistent-token")
    assert bad_beacon_resp.status_code == 404


def test_group_trip_preserves_group_defaults(client: TestClient, mira: dict[str, str]):
    start = date.today() + timedelta(days=30)
    end = start + timedelta(days=7)

    resp = client.post(
        "/api/trips",
        json={
            "name": "Alps Group Trek",
            "destination_name": "Chamonix, France",
            "start_date": start.isoformat(),
            "end_date": end.isoformat(),
            "group_size": 4,
        },
        headers=mira,
    )
    assert resp.status_code == 201
    data = resp.json()
    assert data["trip_type"] == "group"
    assert data["group_size"] == 4
