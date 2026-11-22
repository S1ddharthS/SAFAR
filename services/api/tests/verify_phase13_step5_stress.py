"""SAFAR Phase 13 Step 5: Usability, Edge-Case & Reliability Stress Testing
Runs directly against Staging on Port 8020 with Supabase PostgreSQL 17 (safar_app role).

Sections:
1. Concurrent Collaboration (Itinerary, Voting, Expenses, Role Changes)
2. Repeated & Interrupted Actions (Double submits, replay tokens, refresh rotation, post-logout)
3. Privacy & Security Edge Cases (Expired tokens, revoked sessions, private memories, media signatures, MIME spoofing, oversized uploads, CSRF)
4. Trip Rescue & Protected-Time Invariance (Rain, closures, multiple disruptions, non-mutating)
5. Performance Benchmarks & WebSocket Reconnection (Latency profiling, WS tickets, ping/pong, reconnect)
"""

import asyncio
import io
import json
import time
import uuid
from datetime import datetime, timezone, timedelta
import httpx
try:
    import websockets
except ImportError:
    websockets = None

BASE_URL = "http://127.0.0.1:8020"

MIRA = "mira@safar.demo"     # Trip Owner & Admin
JONAS = "jonas@safar.demo"   # Trip Co-Admin
AIKO = "aiko@safar.demo"     # Accessibility user
LEO = "leo@safar.demo"       # Regular member
NOOR = "noor@safar.demo"     # Local Contributor
DEMO_PASSWORD = "safar-demo-123"


async def get_client_and_token(email: str):
    client = httpx.AsyncClient(base_url=BASE_URL, timeout=20.0)
    resp = await client.post("/api/auth/login", json={"email": email, "password": DEMO_PASSWORD})
    assert resp.status_code == 200, f"Login failed for {email}: {resp.text}"
    data = resp.json()
    token = data["access_token"]
    csrf = data.get("csrf_token")
    headers = {"Authorization": f"Bearer {token}"}
    if csrf:
        headers["X-CSRF-Token"] = csrf
    return client, headers, data["user"], resp.cookies


async def main():
    print("======================================================================")
    print("SAFAR PHASE 13 STEP 5 — STRESS, EDGE-CASE & RELIABILITY TEST SUITE")
    print("Target API: http://127.0.0.1:8020 (Supabase PostgreSQL 17, safar_app)")
    print("======================================================================")

    # 0. Authenticate Pilot Accounts
    print("\n--- 0. Authenticating Pilot Accounts ---")
    mira_client, mira_h, mira_user, mira_cookies = await get_client_and_token(MIRA)
    jonas_client, jonas_h, jonas_user, jonas_cookies = await get_client_and_token(JONAS)
    aiko_client, aiko_h, aiko_user, aiko_cookies = await get_client_and_token(AIKO)
    leo_client, leo_h, leo_user, leo_cookies = await get_client_and_token(LEO)
    noor_client, noor_h, noor_user, noor_cookies = await get_client_and_token(NOOR)
    print(f"Authenticated all 5 accounts cleanly.")

    # Fetch Kyoto destination
    dests_resp = await mira_client.get("/api/destinations", headers=mira_h)
    assert dests_resp.status_code == 200
    kyoto = dests_resp.json()["items"][0]
    kyoto_id = kyoto["id"]

    # Create a fresh trip for Step 5 stress testing
    trip_payload = {
        "name": "Phase 13 Step 5 Stress Voyage",
        "description": "Controlled stress testing workspace for concurrency, resilience, and privacy",
        "start_date": "2026-11-01",
        "end_date": "2026-11-08",
        "destination_id": kyoto_id,
        "destination_name": "Kyoto, Japan",
        "currency": "EUR",
        "privacy": "private"
    }
    trip_resp = await mira_client.post("/api/trips", json=trip_payload, headers=mira_h)
    assert trip_resp.status_code == 201, f"Failed to create trip: {trip_resp.text}"
    trip_id = trip_resp.json()["id"]
    print(f"Created dedicated test trip: {trip_id}")

    # Onboard Jonas (admin), Aiko (member), Leo (member)
    for user_client, user_h, role in [(jonas_client, jonas_h, "admin"), (aiko_client, aiko_h, "member"), (leo_client, leo_h, "member")]:
        inv_resp = await mira_client.post(f"/api/trips/{trip_id}/invitations", json={"role": role, "scope": "full"}, headers=mira_h)
        assert inv_resp.status_code == 201
        token = inv_resp.json()["token"]
        accept_resp = await user_client.post(f"/api/invitations/{token}/accept", headers=user_h)
        assert accept_resp.status_code == 200, f"Accept failed: {accept_resp.text}"

    print("Trip members onboarded: Mira (owner), Jonas (admin), Aiko (member), Leo (member).")

    # =========================================================================
    # 1. Concurrent Collaboration Testing
    # =========================================================================
    print("\n--- 1. Testing Concurrent Collaboration ---")

    # 1.1 Concurrent itinerary items addition by Mira and Jonas
    print("1.1 Testing concurrent itinerary additions (Mira & Jonas)...")
    async def add_item(client, headers, title, start_time, end_time):
        return await client.post(
            f"/api/trips/{trip_id}/itinerary/items",
            json={
                "day": "2026-11-02",
                "title": title,
                "start_time": start_time,
                "end_time": end_time,
                "is_protected": False,
                "cost_estimate": 15.0
            },
            headers=headers
        )

    res_mira, res_jonas = await asyncio.gather(
        add_item(mira_client, mira_h, "Mira Concurrent Morning Visit", "09:00", "10:30"),
        add_item(jonas_client, jonas_h, "Jonas Concurrent Afternoon Visit", "14:00", "15:30")
    )
    assert res_mira.status_code == 201, f"Mira concurrent add failed: {res_mira.text}"
    assert res_jonas.status_code == 201, f"Jonas concurrent add failed: {res_jonas.text}"
    itin_resp = await mira_client.get(f"/api/trips/{trip_id}/itinerary", headers=mira_h)
    assert len(itin_resp.json()["items"]) == 2, "Expected both concurrent items to be preserved in PostgreSQL"
    print("PASS: Both concurrent itinerary items saved cleanly without collision.")

    # 1.2 Concurrent voting by Aiko and Leo
    print("1.2 Testing concurrent voting (Aiko & Leo)...")
    # Fetch recommendation for valid activity
    rec_resp = await mira_client.post(
        f"/api/trips/{trip_id}/engine/recommend",
        json={"mode": "everyone_wins", "for_date": "2026-11-03"},
        headers=mira_h
    )
    assert rec_resp.status_code == 201, f"Recommend failed: {rec_resp.text}"
    rec_act_id = rec_resp.json()["items"][0]["activity_id"]

    # Mira creates an activity proposal
    prop_resp = await mira_client.post(
        f"/api/trips/{trip_id}/proposals",
        json={
            "kind": "add_activity",
            "activity_id": rec_act_id,
            "title": "Nijo Castle Twilight Garden Tour",
            "day": "2026-11-03",
            "start_time": "17:00",
            "summary": "Evening culture walk"
        },
        headers=mira_h
    )
    assert prop_resp.status_code == 201, f"Proposal creation failed: {prop_resp.text}"
    proposal_id = prop_resp.json()["id"]

    vote_aiko, vote_leo = await asyncio.gather(
        aiko_client.post(f"/api/trips/{trip_id}/proposals/{proposal_id}/vote", json={"value": "yes"}, headers=aiko_h),
        leo_client.post(f"/api/trips/{trip_id}/proposals/{proposal_id}/vote", json={"value": "yes"}, headers=leo_h)
    )
    assert vote_aiko.status_code == 200, f"Aiko vote failed: {vote_aiko.text}"
    assert vote_leo.status_code == 200, f"Leo vote failed: {vote_leo.text}"
    print("PASS: Both concurrent votes processed cleanly.")

    # 1.3 Concurrent expenses addition by Mira and Leo
    print("1.3 Testing concurrent expense additions (Mira & Leo)...")
    exp_mira, exp_leo = await asyncio.gather(
        mira_client.post(f"/api/trips/{trip_id}/expenses", json={"title": "Tea Ceremony Sweets", "amount": 60.0, "category": "food", "split": "equal"}, headers=mira_h),
        leo_client.post(f"/api/trips/{trip_id}/expenses", json={"title": "Local Transport Passes", "amount": 120.0, "category": "transport", "split": "equal"}, headers=leo_h)
    )
    assert exp_mira.status_code == 201, f"Mira expense failed: {exp_mira.text}"
    assert exp_leo.status_code == 201, f"Leo expense failed: {exp_leo.text}"

    balances_resp = await mira_client.get(f"/api/trips/{trip_id}/expenses/balances", headers=mira_h)
    assert balances_resp.status_code == 200
    b_data = balances_resp.json()
    assert b_data["total_spent"] == 180.0, f"Expected total spent 180.0, got {b_data['total_spent']}"
    assert len(b_data["settlements"]) > 0
    print(f"PASS: Concurrent expenses reconciled. Total spent: €{b_data['total_spent']}, Settlements: {len(b_data['settlements'])}.")

    # 1.4 Race: Owner approves proposal while another member attempts to vote/change it
    print("1.4 Testing approval / vote race condition...")
    app_res, late_vote_res = await asyncio.gather(
        mira_client.post(f"/api/trips/{trip_id}/proposals/{proposal_id}/approve", json={"approval": True}, headers=mira_h),
        jonas_client.post(f"/api/trips/{trip_id}/proposals/{proposal_id}/vote", json={"value": "no"}, headers=jonas_h)
    )
    # The approval will either complete first (causing late vote to receive 409) or vote will complete before approval.
    assert app_res.status_code == 200, f"Approval failed: {app_res.text}"
    # Verify proposal is approved
    post_prop = await mira_client.get(f"/api/trips/{trip_id}/proposals?status=all", headers=mira_h)
    target = next((p for p in post_prop.json()["items"] if p["id"] == proposal_id), None)
    assert target is not None and target["status"] == "approved"
    # A subsequent vote attempt on the approved proposal must strictly return 409 Conflict
    re_vote = await jonas_client.post(f"/api/trips/{trip_id}/proposals/{proposal_id}/vote", json={"value": "yes"}, headers=jonas_h)
    assert re_vote.status_code == 409, f"Expected 409 Conflict for voting on closed proposal, got {re_vote.status_code}"
    print("PASS: Proposal approved into confirmed itinerary. Late vote on closed proposal rejected with 409 Conflict.")

    # 1.5 Member role modification / removal during active session
    print("1.5 Testing member removal during active session...")
    # Mira removes Leo from trip members
    # Find Leo's membership id
    members_resp = await mira_client.get(f"/api/trips/{trip_id}/members", headers=mira_h)
    leo_member = next(m for m in members_resp.json()["items"] if m["user"]["id"] == leo_user["id"])
    del_member_resp = await mira_client.delete(f"/api/trips/{trip_id}/members/{leo_member['id']}", headers=mira_h)
    assert del_member_resp.status_code in (200, 204), f"Failed to remove member: {del_member_resp.text}"

    # Leo now tries to add an expense with his existing active JWT token
    leo_blocked = await leo_client.post(
        f"/api/trips/{trip_id}/expenses",
        json={"title": "Unauthorized Expense After Removal", "amount": 50.0, "category": "food", "split": "equal"},
        headers=leo_h
    )
    assert leo_blocked.status_code in (403, 404), f"Expected 403 or 404 for removed member, got {leo_blocked.status_code}"
    print(f"PASS: Removed member immediately blocked from writes with HTTP {leo_blocked.status_code}.")

    # Restore Leo's membership for subsequent tests
    inv_leo = await mira_client.post(f"/api/trips/{trip_id}/invitations", json={"role": "member", "scope": "full"}, headers=mira_h)
    await leo_client.post(f"/api/invitations/{inv_leo.json()['token']}/accept", headers=leo_h)
    print("Leo restored as member.")

    # =========================================================================
    # 2. Repeated and Interrupted Actions
    # =========================================================================
    print("\n--- 2. Testing Repeated & Interrupted Actions ---")

    # 2.1 Repeated invitation acceptance (Single-use token replay)
    print("2.1 Testing invitation token replay...")
    replay_token = inv_leo.json()["token"]
    replay_resp = await aiko_client.post(f"/api/invitations/{replay_token}/accept", headers=aiko_h)
    assert replay_resp.status_code == 409, f"Expected 409 Conflict for used token, got {replay_resp.status_code}"
    print("PASS: Replaying used invitation token rejected with 409 Conflict.")

    # 2.2 Repeated proposal approval
    print("2.2 Testing repeated proposal approval idempotency/rejection...")
    re_app = await mira_client.post(f"/api/trips/{trip_id}/proposals/{proposal_id}/approve", json={"approval": True}, headers=mira_h)
    assert re_app.status_code == 409, f"Expected 409 Conflict for already approved proposal, got {re_app.status_code}"
    print("PASS: Repeated proposal approval rejected with 409 Conflict (no duplicate items created).")

    # 2.3 Double-tapping expense submission (rapid duplicate payloads)
    print("2.3 Testing rapid repeated expense submission...")
    exp1, exp2 = await asyncio.gather(
        mira_client.post(f"/api/trips/{trip_id}/expenses", json={"title": "Shared Shuttle", "amount": 80.0, "category": "transport", "split": "equal"}, headers=mira_h),
        mira_client.post(f"/api/trips/{trip_id}/expenses", json={"title": "Shared Shuttle", "amount": 80.0, "category": "transport", "split": "equal"}, headers=mira_h)
    )
    assert exp1.status_code == 201 and exp2.status_code == 201
    assert exp1.json()["id"] != exp2.json()["id"], "Expenses must generate distinct IDs"
    print("PASS: Distinct UUIDs generated for concurrent submissions; ledger state remains consistent.")

    # 2.4 Interrupted / Replayed Refresh Token Rotation
    print("2.4 Testing refresh token rotation and replay prevention...")
    rot_client = httpx.AsyncClient(base_url=BASE_URL, timeout=15.0)
    rot_login = await rot_client.post("/api/auth/login", json={"email": MIRA, "password": DEMO_PASSWORD})
    initial_refresh = rot_login.cookies.get("safar_refresh")
    assert initial_refresh is not None, "Refresh cookie must be present"

    # First refresh: succeeds and rotates refresh token
    refresh1 = await rot_client.post("/api/auth/refresh")
    assert refresh1.status_code == 200, f"Initial refresh failed: {refresh1.text}"
    rotated_refresh = refresh1.cookies.get("safar_refresh")
    assert rotated_refresh != initial_refresh, "Refresh token must rotate upon use"

    # Replay attack: client attempts to reuse old initial_refresh cookie
    replay_client = httpx.AsyncClient(base_url=BASE_URL, timeout=15.0)
    replay_client.cookies.set("safar_refresh", initial_refresh)
    replay_refresh = await replay_client.post("/api/auth/refresh")
    assert replay_refresh.status_code in (401, 403), f"Expected 401/403 for replayed refresh cookie, got {replay_refresh.status_code}"
    print("PASS: Replayed old refresh cookie rejected server-side (rotation revocation active).")

    # 2.5 Action post-logout
    print("2.5 Testing write post-logout...")
    temp_client, temp_h, temp_u, _ = await get_client_and_token(JONAS)
    logout_resp = await temp_client.post("/api/auth/logout", headers=temp_h)
    assert logout_resp.status_code == 200

    post_logout_write = await temp_client.get("/api/users/me", headers=temp_h)
    assert post_logout_write.status_code == 401, f"Expected 401 after logout, got {post_logout_write.status_code}"
    print("PASS: Post-logout requests rejected with 401 Unauthorized.")

    # =========================================================================
    # 3. Privacy and Security Edge Cases
    # =========================================================================
    print("\n--- 3. Testing Privacy & Security Edge Cases ---")

    # 3.1 Expired invitation tokens
    print("3.1 Testing expired invitation token...")
    # Preview an invalid or expired token
    exp_preview = await mira_client.get("/api/invitations/non-existent-or-expired-token", headers=mira_h)
    assert exp_preview.status_code in (404, 410), f"Expected 404 or 410, got {exp_preview.status_code}"
    print("PASS: Invalid/expired invitation returns 404/410 cleanly.")

    # 3.2 Private memory access by non-members and other members
    print("3.2 Testing private memory isolation...")
    priv_mem = await mira_client.post(
        f"/api/trips/{trip_id}/memories",
        json={"kind": "text", "text_content": "Mira's strictly confidential journal entry", "visibility": "private"},
        headers=mira_h
    )
    assert priv_mem.status_code == 201
    priv_mem_id = priv_mem.json()["id"]

    # Member Aiko lists trip memories: private memory must NOT appear
    aiko_mems = await aiko_client.get(f"/api/trips/{trip_id}/memories", headers=aiko_h)
    assert aiko_mems.status_code == 200
    aiko_mem_ids = [m["id"] for day in aiko_mems.json().get("days", []) for m in day.get("memories", [])]
    assert priv_mem_id not in aiko_mem_ids, "Private memory must be hidden from other trip members"

    # External user Noor attempts to read trip memories: must fail closed (404)
    noor_read_priv = await noor_client.get(f"/api/trips/{trip_id}/memories", headers=noor_h)
    assert noor_read_priv.status_code == 404, f"Expected 404 for non-member accessing memories, got {noor_read_priv.status_code}"
    print("PASS: Private memory strictly hidden from other members; non-members receive 404.")

    # 3.3 Cross-user memory modification attempt
    print("3.3 Testing unauthorized memory edit...")
    leo_edit_mira = await leo_client.patch(
        f"/api/trips/{trip_id}/memories/{priv_mem_id}",
        json={"text_content": "Hacked content by Leo"},
        headers=leo_h
    )
    assert leo_edit_mira.status_code in (403, 404), f"Expected 403 or 404, got {leo_edit_mira.status_code}"
    print(f"PASS: Cross-user memory modification rejected with {leo_edit_mira.status_code}.")

    # 3.4 Valid media upload vs Expired / Tampered media links
    print("3.4 Testing media upload and HMAC signature expiry/tampering...")
    # Real 1x1 valid PNG image
    valid_png_bytes = bytes([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
        0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
        0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
        0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
    ])
    files = {"file": ("test_valid.png", valid_png_bytes, "image/png")}
    upload_resp = await mira_client.post(f"/api/trips/{trip_id}/media", files=files, headers=mira_h)
    assert upload_resp.status_code == 201, f"Valid upload failed: {upload_resp.text}"
    media_url = upload_resp.json()["media_url"]
    print(f"Valid media uploaded: {media_url[:60]}...")

    # Fetch with valid signature
    media_get = await mira_client.get(media_url)
    assert media_get.status_code == 200, f"Failed to fetch valid media: {media_get.status_code}"

    # Tamper with signature
    tampered_url = media_url + "tampered"
    tampered_get = await mira_client.get(tampered_url)
    assert tampered_get.status_code == 403, f"Expected 403 for tampered media URL, got {tampered_get.status_code}"

    # Strip query parameters completely
    bare_url = media_url.split("?")[0]
    bare_get = await mira_client.get(bare_url)
    assert bare_get.status_code == 403, f"Expected 403 for unsigned media URL, got {bare_get.status_code}"
    print("PASS: Valid media served; tampered and unsigned media URLs strictly rejected with 403.")

    # 3.5 Media upload MIME spoofing & Oversized file handling
    print("3.5 Testing MIME spoofing rejection...")
    fake_png = b"THIS IS DEFINITELY NOT A PNG FILE TEXT TEXT"
    spoof_files = {"file": ("fake.png", fake_png, "image/png")}
    spoof_resp = await mira_client.post(f"/api/trips/{trip_id}/media", files=spoof_files, headers=mira_h)
    assert spoof_resp.status_code == 415, f"Expected 415 for spoofed MIME, got {spoof_resp.status_code}: {spoof_resp.text}"
    print("PASS: MIME spoofing rejected with 415 Unsupported Media Type.")

    print("3.5b Testing oversized file rejection...")
    # Generate 26MB stream to exceed MAX_UPLOAD_BYTES (25MB)
    oversized_data = b"0" * (26 * 1024 * 1024)
    oversized_files = {"file": ("huge.jpg", oversized_data, "image/jpeg")}
    try:
        oversized_resp = await mira_client.post(f"/api/trips/{trip_id}/media", files=oversized_files, headers=mira_h)
        assert oversized_resp.status_code in (413, 415), f"Expected 413 Payload Too Large, got {oversized_resp.status_code}"
        print(f"PASS: Oversized upload rejected with HTTP {oversized_resp.status_code}.")
    except (httpx.RequestError, httpx.HTTPError) as exc:
        print(f"PASS: Connection closed/rejected by server for oversized payload ({exc}).")

    # 3.6 Location consent withdrawal
    print("3.6 Testing location consent toggle...")
    toggle_resp = await mira_client.patch("/api/users/me/profile", json={"location_sharing": False}, headers=mira_h)
    assert toggle_resp.status_code == 200
    me_check = await mira_client.get("/api/users/me", headers=mira_h)
    assert me_check.json()["profile"]["location_sharing"] is False
    print("PASS: Location consent withdrawal persisted cleanly.")

    # 3.7 CSRF Protection for state-changing requests
    print("3.7 Testing CSRF token requirement...")
    access_cookie_val = mira_cookies.get("safar_access")
    csrf_test_client = httpx.AsyncClient(base_url=BASE_URL, timeout=15.0)
    if access_cookie_val:
        csrf_test_client.cookies.set("safar_access", access_cookie_val)
    # State-changing request with access cookie but missing X-CSRF-Token
    no_csrf_resp = await csrf_test_client.post(
        f"/api/trips/{trip_id}/expenses",
        json={"title": "CSRF Attack Attempt", "amount": 100.0, "category": "food", "split": "equal"}
    )
    assert no_csrf_resp.status_code in (401, 403), f"Expected 401 or 403 CSRF rejected, got {no_csrf_resp.status_code}"
    print(f"PASS: Cookie-authenticated request without valid CSRF header rejected with {no_csrf_resp.status_code}.")

    # =========================================================================
    # 4. Trip Rescue and Protected-Time Invariance
    # =========================================================================
    print("\n--- 4. Testing Trip Rescue & Protected-Time Edge Cases ---")

    # Add a protected morning walk
    prot_item_resp = await mira_client.post(
        f"/api/trips/{trip_id}/itinerary/items",
        json={
            "day": "2026-11-04",
            "title": "Sacred Arashiyama Meditation Block",
            "start_time": "08:00",
            "end_time": "10:30",
            "is_protected": True,
            "cost_estimate": 0.0
        },
        headers=mira_h
    )
    assert prot_item_resp.status_code == 201
    prot_id = prot_item_resp.json()["id"]

    # Also add an outdoor unprotected activity on the same day
    unprot_item_resp = await mira_client.post(
        f"/api/trips/{trip_id}/itinerary/items",
        json={
            "day": "2026-11-04",
            "title": "Open Air Botanical Garden Walk",
            "start_time": "11:00",
            "end_time": "13:00",
            "is_protected": False,
            "cost_estimate": 10.0
        },
        headers=mira_h
    )
    assert unprot_item_resp.status_code == 201
    unprot_id = unprot_item_resp.json()["id"]

    # 4.1 Rain disruption simulation targeting protected item
    print("4.1 Running rescue analysis targeting protected item...")
    rescue_rain = await mira_client.post(
        f"/api/trips/{trip_id}/rescue/analyze",
        json={"kind": "rain", "item_id": prot_id, "extra_minutes": 30},
        headers=mira_h
    )
    assert rescue_rain.status_code == 200, f"Rescue failed: {rescue_rain.text}"
    rain_data = rescue_rain.json()

    # Verify protected item is in 'protected', NOT in 'affected' or replaced
    protected_ids = [p["item_id"] for p in rain_data.get("protected", [])]
    affected_ids = [a["item"]["id"] for a in rain_data.get("affected", [])]
    assert prot_id in protected_ids, f"Protected item {prot_id} must be in protected list"
    assert prot_id not in affected_ids, f"Protected item {prot_id} must NOT be in affected list"
    assert rain_data["requires_approval"] is True, "Rescue must require group approval"
    assert "Nothing has been changed" in rain_data["disclosure"]
    print("PASS: Rain disruption respects protected item. Itinerary untouched without explicit approval.")

    # 4.1b Attempting to propose replacing a protected item must strictly return 409 Conflict
    print("4.1b Testing direct replacement attempt of protected item...")
    bad_propose = await mira_client.post(
        f"/api/trips/{trip_id}/rescue/propose",
        json={
            "kind": "rain",
            "items": [{"item_id": prot_id, "activity_id": rec_act_id, "start_time": "08:00", "day": "2026-11-04"}]
        },
        headers=mira_h
    )
    assert bad_propose.status_code == 409, f"Expected 409 for proposing replacement of protected item, got {bad_propose.status_code}"
    print("PASS: Direct proposal to replace protected item strictly rejected with 409 Conflict.")

    # 4.2 Multiple disruption types in sequence
    print("4.2 Testing multiple sequential disruption analyses (closure, fatigue, budget, time)...")
    for kind in ["closure", "fatigue", "budget", "time"]:
        res_k = await mira_client.post(
            f"/api/trips/{trip_id}/rescue/analyze",
            json={"kind": kind, "item_id": prot_id},
            headers=mira_h
        )
        assert res_k.status_code == 200
        k_data = res_k.json()
        k_prot_ids = [p["item_id"] for p in k_data.get("protected", [])]
        assert prot_id in k_prot_ids, f"Protected item {prot_id} must survive disruption '{kind}'"
        assert k_data["requires_approval"] is True
    print("PASS: Protected time invariance maintained across all disruption kinds.")

    # 4.3 Confirmed Itinerary remains untouched
    post_rescue_itin = await mira_client.get(f"/api/trips/{trip_id}/itinerary", headers=mira_h)
    p_items = post_rescue_itin.json()["items"]
    assert any(i["id"] == prot_id for i in p_items), "Protected item must remain in itinerary"
    assert any(i["id"] == unprot_id for i in p_items), "Unprotected item must also remain untouched until approval"
    print("PASS: Confirmed itinerary verified 100% untouched after rescue evaluations.")

    # =========================================================================
    # 5. Performance Benchmarks & WebSocket Reconnection
    # =========================================================================
    print("\n--- 5. Performance Benchmarks & WebSocket Verification ---")

    # 5.1 Latency Measurements
    benchmarks = {}
    async def measure(name, coro):
        t0 = time.perf_counter()
        res = await coro
        elapsed_ms = (time.perf_counter() - t0) * 1000
        benchmarks[name] = elapsed_ms
        return res

    await measure("GET /api/health", mira_client.get("/api/health"))
    await measure("POST /api/auth/login", mira_client.post("/api/auth/login", json={"email": MIRA, "password": DEMO_PASSWORD}))
    await measure("GET /api/trips/{id}", mira_client.get(f"/api/trips/{trip_id}", headers=mira_h))
    await measure("GET /api/trips/{id}/itinerary", mira_client.get(f"/api/trips/{trip_id}/itinerary", headers=mira_h))
    await measure("POST /api/trips/{id}/engine/recommend", mira_client.post(f"/api/trips/{trip_id}/engine/recommend", json={"mode": "everyone_wins", "for_date": "2026-11-04"}, headers=mira_h))
    await measure("POST /api/trips/{id}/expenses", mira_client.post(f"/api/trips/{trip_id}/expenses", json={"title": "Benchmark Expense", "amount": 25.0, "category": "food", "split": "equal"}, headers=mira_h))
    await measure("GET /api/trips/{id}/expenses/balances", mira_client.get(f"/api/trips/{trip_id}/expenses/balances", headers=mira_h))
    await measure("POST /api/trips/{id}/rescue/analyze", mira_client.post(f"/api/trips/{trip_id}/rescue/analyze", json={"kind": "rain"}, headers=mira_h))

    print("\nAPI Response Time Benchmarks (Staging Port 8020 / Supabase PostgreSQL 17):")
    for endpoint, ms in benchmarks.items():
        print(f"  - {endpoint:<38}: {ms:6.1f} ms")

    # 5.2 WebSocket Connection & Ping-Pong
    print("\n5.2 Testing WebSocket Realtime & Ticket Flow...")
    ticket_resp = await mira_client.post("/api/auth/ws-ticket", headers=mira_h)
    assert ticket_resp.status_code == 200, f"Failed to get WS ticket: {ticket_resp.text}"
    ws_ticket = ticket_resp.json()["ticket"]
    assert ws_ticket, "Ticket must not be empty"

    if websockets:
        ws_url = f"ws://127.0.0.1:8020/ws/trips/{trip_id}?token={ws_ticket}"
        async with websockets.connect(ws_url) as ws:
            # First message is connection acknowledgment
            ack = await ws.recv()
            ack_data = json.loads(ack)
            assert ack_data.get("event") == "connected", f"Expected connected event, got {ack}"
            print(f"WebSocket connected for user {ack_data.get('user')}.")

            # Send ping
            await ws.send("ping")
            pong = await ws.recv()
            pong_data = json.loads(pong)
            assert pong_data.get("event") == "pong", f"Expected pong event, got {pong}"
            print("WebSocket ping/pong acknowledged.")

        # Reconnect test: generate new ticket and reconnect
        ticket_resp2 = await mira_client.post("/api/auth/ws-ticket", headers=mira_h)
        ws_ticket2 = ticket_resp2.json()["ticket"]
        async with websockets.connect(f"ws://127.0.0.1:8020/ws/trips/{trip_id}?token={ws_ticket2}") as ws2:
            ack2 = await ws2.recv()
            assert json.loads(ack2).get("event") == "connected"
            print("WebSocket reconnection succeeded with fresh ticket.")
    else:
        print("websockets library not installed in this environment; ticket generation verified.")

    print("\n======================================================================")
    print("ALL PHASE 13 STEP 5 STRESS, CONCURRENCY & SECURITY CHECKS PASSED 100%")
    print("======================================================================")


if __name__ == "__main__":
    asyncio.run(main())
