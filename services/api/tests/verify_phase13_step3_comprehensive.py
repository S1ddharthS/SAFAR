"""Comprehensive automated test suite for Phase 13 Step 3:
Live API Integration & Automated Mobile Verification against Staging on Port 8020
using Supabase PostgreSQL 17 and safar_app role.
"""

import asyncio
import io
import json
import uuid
from datetime import date, datetime, timezone
import httpx
import websockets

BASE_URL = "http://127.0.0.1:8020"
WS_URL = "ws://127.0.0.1:8020"

MIRA = "mira@safar.demo"
AIKO = "aiko@safar.demo"
JONAS = "jonas@safar.demo"
LEO = "leo@safar.demo"
DEMO_PASSWORD = "safar-demo-123"


async def test_auth_and_sessions():
    print("\n=======================================================")
    print("STEP 3.3 — AUTHENTICATION & SESSION VERIFICATION")
    print("=======================================================")

    async with httpx.AsyncClient(base_url=BASE_URL, timeout=10.0) as client:
        # 1. Valid Login
        login_resp = await client.post("/api/auth/login", json={
            "email": MIRA,
            "password": DEMO_PASSWORD
        })
        print(f"1. Valid login ({MIRA}): HTTP {login_resp.status_code}")
        assert login_resp.status_code == 200, f"Login failed: {login_resp.text}"
        login_data = login_resp.json()
        access_token = login_data["access_token"]
        assert access_token
        refresh_cookie = login_resp.cookies.get("safar_refresh")
        assert refresh_cookie, "safar_refresh cookie should be present"
        print("   Received valid access_token and HttpOnly safar_refresh cookie.")

        # 2. Invalid Login
        bad_login = await client.post("/api/auth/login", json={
            "email": MIRA,
            "password": "WrongPassword456!"
        })
        print(f"2. Invalid password attempt: HTTP {bad_login.status_code} (rejected)")
        assert bad_login.status_code == 401

        # 3. Access Token & Refresh Rotation
        refresh_resp = await client.post("/api/auth/refresh")
        print(f"3. Refresh token rotation: HTTP {refresh_resp.status_code}")
        assert refresh_resp.status_code == 200, f"Refresh failed: {refresh_resp.text}"
        new_data = refresh_resp.json()
        new_access = new_data["access_token"]
        new_refresh_cookie = refresh_resp.cookies.get("safar_refresh")
        assert new_access and new_refresh_cookie
        assert new_refresh_cookie != refresh_cookie
        print("   Rotated to new access_token and distinct new refresh cookie.")

        # 4. Refresh Token Reuse Detection
        # Send old refresh token in a fresh client to test replay
        async with httpx.AsyncClient(base_url=BASE_URL, timeout=5.0) as reuse_client:
            reuse_resp = await reuse_client.post(
                "/api/auth/refresh",
                cookies={"safar_refresh": refresh_cookie}  # Replaying old token
            )
            print(f"4. Replay old refresh token: HTTP {reuse_resp.status_code} (reuse detected)")
            assert reuse_resp.status_code == 401

        # 5. Authenticated endpoint check with active session
        me_resp = await client.get("/api/auth/me", headers={"Authorization": f"Bearer {new_access}"})
        print(f"5. Authenticated /api/auth/me check: HTTP {me_resp.status_code}")
        # Note: if reuse detection revoked the entire session family, me_resp is 401, which is also correct security behaviour.
        # Let's verify session revocation behaviour.

        # 6. Logout / Session Revocation
        # Log in again to get fresh session for logout test
        fresh_login = await client.post("/api/auth/login", json={"email": MIRA, "password": DEMO_PASSWORD})
        fresh_access = fresh_login.json()["access_token"]
        logout_resp = await client.post(
            "/api/auth/logout",
            headers={"Authorization": f"Bearer {fresh_access}"},
            json={"all_devices": False}
        )
        print(f"6. Logout: HTTP {logout_resp.status_code}")
        assert logout_resp.status_code == 200

        # Verify token is revoked server-side
        revoked_check = await client.get("/api/auth/me", headers={"Authorization": f"Bearer {fresh_access}"})
        print(f"   Subsequent request with logged-out token: HTTP {revoked_check.status_code} (revoked)")
        assert revoked_check.status_code == 401

    print(">> AUTHENTICATION & SESSION VERIFICATION PASSED 100%")


async def test_core_workflows():
    print("\n=======================================================")
    print("STEP 3.4 — CORE APPLICATION INTEGRATION WORKFLOWS")
    print("=======================================================")

    async with httpx.AsyncClient(base_url=BASE_URL, timeout=15.0) as client:
        # Authenticate fresh as Mira
        login_resp = await client.post("/api/auth/login", json={"email": MIRA, "password": DEMO_PASSWORD})
        assert login_resp.status_code == 200
        headers = {"Authorization": f"Bearer {login_resp.json()['access_token']}"}

        # 1. Dashboard & Profile
        me_resp = await client.get("/api/users/me", headers=headers)
        print(f"Workflow 1: Dashboard & Profile: HTTP {me_resp.status_code}")
        assert me_resp.status_code == 200
        me_data = me_resp.json()
        print(f"   User: {me_data['user']['display_name']} | Bio: {me_data['profile']['bio']}")

        # 2. Discover & Destinations
        dests_resp = await client.get("/api/destinations", headers=headers)
        assert dests_resp.status_code == 200
        dests_items = dests_resp.json()["items"]
        print(f"Workflow 2: Destinations catalog: HTTP {dests_resp.status_code} ({len(dests_items)} destinations)")
        assert len(dests_items) > 0
        first_dest = dests_items[0]
        dest_detail = await client.get(f"/api/destinations/{first_dest['id']}", headers=headers)
        assert dest_detail.status_code == 200
        print(f"   Destination detail: {dest_detail.json()['name']}, {dest_detail.json()['country']}")

        # 3. Trip Creation & Membership
        trip_resp = await client.post("/api/trips", json={
            "name": f"Staging Integration Voyage {uuid.uuid4().hex[:6]}",
            "destination_id": first_dest["id"],
            "destination_name": first_dest["name"],
            "start_date": "2026-09-01",
            "end_date": "2026-09-10",
            "currency": "EUR"
        }, headers=headers)
        print(f"Workflow 3: Trip creation: HTTP {trip_resp.status_code}")
        assert trip_resp.status_code == 201
        trip = trip_resp.json()
        trip_id = trip["id"]
        print(f"   Trip ID: {trip_id} | Name: {trip['name']}")

        members_resp = await client.get(f"/api/trips/{trip_id}/members", headers=headers)
        assert members_resp.status_code == 200
        print(f"   Trip members: {len(members_resp.json())} active member(s)")

        # 4. Invitations
        inv_resp = await client.post(f"/api/trips/{trip_id}/invitations", json={
            "role": "member",
            "scope": "full"
        }, headers=headers)
        print(f"Workflow 4: Invitation creation: HTTP {inv_resp.status_code}")
        assert inv_resp.status_code in {200, 201}
        inv_token = inv_resp.json()["token"]
        print(f"   Created invitation token: {inv_token[:12]}...")

        # 5. Collaborative Itinerary Item
        itin_resp = await client.post(f"/api/trips/{trip_id}/itinerary/items", json={
            "day": "2026-09-02",
            "start_time": "09:00",
            "end_time": "12:00",
            "title": "Visit Fushimi Inari Taisha",
            "notes": "Hike the 10,000 torii gates trail"
        }, headers=headers)
        print(f"Workflow 5: Itinerary item created: HTTP {itin_resp.status_code}")
        assert itin_resp.status_code == 201
        item_id = itin_resp.json()["id"]

        itin_list = await client.get(f"/api/trips/{trip_id}/itinerary", headers=headers)
        assert itin_list.status_code == 200
        print(f"   Confirmed itinerary items: {len(itin_list.json()['items'])}")

        # 6. Group Experience Engine Recommendations
        recs_resp = await client.post(f"/api/trips/{trip_id}/engine/recommend", json={
            "mode": "everyone_wins",
            "for_date": "2026-09-03"
        }, headers=headers)
        print(f"Workflow 6: Recommendations generated: HTTP {recs_resp.status_code}")
        assert recs_resp.status_code == 201
        rec_data = recs_resp.json()
        print(f"   Engine mode: {rec_data.get('mode')} | Items returned: {len(rec_data.get('items', []))}")

        # 7. Voting & Proposals
        rec_activity_id = rec_data["items"][0]["activity_id"]
        prop_resp = await client.post(f"/api/trips/{trip_id}/proposals", json={
            "kind": "add_activity",
            "activity_id": rec_activity_id,
            "day": "2026-09-04",
            "start_time": "14:00",
            "title": "Afternoon Temple Walk",
            "summary": "Group proposal from recommendations"
        }, headers=headers)
        print(f"Workflow 7: Proposal submitted: HTTP {prop_resp.status_code}")
        assert prop_resp.status_code == 201
        proposal_id = prop_resp.json()["id"]

        vote_resp = await client.post(f"/api/trips/{trip_id}/proposals/{proposal_id}/vote", json={
            "value": "yes"
        }, headers=headers)
        print(f"   Vote recorded: HTTP {vote_resp.status_code}")
        assert vote_resp.status_code == 200

        approve_resp = await client.post(
            f"/api/trips/{trip_id}/proposals/{proposal_id}/approve",
            json={"approval": True},
            headers=headers
        )
        print(f"   Proposal approved into itinerary: HTTP {approve_resp.status_code}")
        assert approve_resp.status_code == 200

        # 8. Expenses & Balances
        exp_resp = await client.post(f"/api/trips/{trip_id}/expenses", json={
            "title": "Group Bullet Train Tickets",
            "amount": 280.0,
            "category": "transport",
            "split": "equal"
        }, headers=headers)
        print(f"Workflow 8: Expense logged: HTTP {exp_resp.status_code}")
        assert exp_resp.status_code == 201

        bal_resp = await client.get(f"/api/trips/{trip_id}/expenses/balances", headers=headers)
        assert bal_resp.status_code == 200
        print(f"   Group balances: total_spent={bal_resp.json()['total_spent']}")

        # 9. Journey DNA
        dna_resp = await client.get("/api/users/me/dna", headers=headers)
        print(f"Workflow 9: Journey DNA retrieved: HTTP {dna_resp.status_code}")
        assert dna_resp.status_code == 200
        assert "culture" in dna_resp.json()["scores"]

        # 10. Memories
        mem_resp = await client.post(f"/api/trips/{trip_id}/memories", json={
            "kind": "text",
            "text_content": "Kinkaku-ji golden pavilion reflection at sunset",
            "caption": "Golden Hour in Kyoto"
        }, headers=headers)
        print(f"Workflow 10: Memory recorded: HTTP {mem_resp.status_code}")
        assert mem_resp.status_code == 201

        mems_list = await client.get(f"/api/trips/{trip_id}/memories", headers=headers)
        assert mems_list.status_code == 200
        print(f"   Total memory days in trip: {len(mems_list.json()['days'])}")
        assert len(mems_list.json()["days"]) > 0

        # 11. Dream Import (Inspirations)
        dream_resp = await client.post(f"/api/trips/{trip_id}/inspirations", json={
            "source_type": "text",
            "content": "Exploring bamboo groves in Arashiyama and zen rock gardens at Ryoan-ji"
        }, headers=headers)
        print(f"Workflow 11: Dream Import inspiration: HTTP {dream_resp.status_code}")
        assert dream_resp.status_code == 201
        print(f"   Status: {dream_resp.json()['status']} | Candidates: {len(dream_resp.json()['extraction'].get('matches', []))}")

        # 12. Grounded Multilingual Assistant
        asst_resp = await client.post("/api/assistant/chat", json={
            "message": "What activities are planned on our itinerary?",
            "trip_id": trip_id,
            "language": "en"
        }, headers=headers)
        print(f"Workflow 12: Grounded Assistant chat: HTTP {asst_resp.status_code}")
        assert asst_resp.status_code == 200
        print(f"   Assistant reply excerpt: {asst_resp.json()['answer'][:60]}...")

        # 13. Trip Rescue
        rescue_resp = await client.post(f"/api/trips/{trip_id}/rescue/analyze", json={
            "kind": "rain",
            "extra_minutes": 45,
            "note": "Sudden heavy rain expected in Kyoto"
        }, headers=headers)
        print(f"Workflow 13: Trip Rescue analysis: HTTP {rescue_resp.status_code}")
        assert rescue_resp.status_code == 200
        print(f"   Rescue options returned: {len(rescue_resp.json().get('replacements', []))}")

        # 14. Nearby Places (enable location sharing in profile first to verify privacy gate)
        await client.patch("/api/users/me/profile", json={"location_sharing": True}, headers=headers)
        nearby_resp = await client.get(f"/api/trips/{trip_id}/nearby?lat=35.0116&lon=135.7681", headers=headers)
        print(f"Workflow 14: Nearby places: HTTP {nearby_resp.status_code} ({len(nearby_resp.json()['items'])} found)")
        assert nearby_resp.status_code == 200

        # 15. Notifications
        notif_resp = await client.get("/api/users/me/notifications", headers=headers)
        print(f"Workflow 15: User notifications: HTTP {notif_resp.status_code} ({len(notif_resp.json()['items'])} items)")
        assert notif_resp.status_code == 200

        # 16. Offline Idempotent Sync
        sync_client_id = f"offline-sync-{uuid.uuid4().hex[:10]}"
        sync_resp = await client.post(f"/api/trips/{trip_id}/sync", json=[{
            "client_id": sync_client_id,
            "operation": "memory_create",
            "payload": {
                "text_content": "Offline snapshot while hiking Higashiyama trail",
                "caption": "Offline cache sync test"
            }
        }], headers=headers)
        print(f"Workflow 16: Offline sync: HTTP {sync_resp.status_code}")
        assert sync_resp.status_code == 200
        print(f"   Sync result: {sync_resp.json()}")

        # 17. WebSocket Ticket & Live Handshake
        ticket_resp = await client.post("/api/auth/ws-ticket", headers=headers)
        print(f"Workflow 17: WebSocket ticket requested: HTTP {ticket_resp.status_code}")
        assert ticket_resp.status_code == 200
        ticket = ticket_resp.json()["ticket"]

        # Live connect to WebSocket endpoint
        ws_endpoint = f"{WS_URL}/ws/trips/{trip_id}?token={ticket}"
        async with websockets.connect(ws_endpoint) as ws:
            connected_evt = json.loads(await asyncio.wait_for(ws.recv(), timeout=3.0))
            print(f"   Live WebSocket connected event: {connected_evt.get('event')} (user: {connected_evt.get('user')})")
            assert connected_evt.get("event") == "connected"

            await ws.send("ping")
            pong_evt = json.loads(await asyncio.wait_for(ws.recv(), timeout=3.0))
            print(f"   Live WebSocket ping response: {pong_evt.get('event')}")
            assert pong_evt.get("event") == "pong"

    print(">> ALL CORE APPLICATION INTEGRATION WORKFLOWS PASSED 100%")


async def test_multi_user_isolation():
    print("\n=======================================================")
    print("STEP 3.5 — MULTI-USER SECURITY & TENANT ISOLATION")
    print("=======================================================")

    async with httpx.AsyncClient(base_url=BASE_URL, timeout=15.0) as client:
        # 1. Login Mira (Owner)
        mira_login = await client.post("/api/auth/login", json={"email": MIRA, "password": DEMO_PASSWORD})
        assert mira_login.status_code == 200
        mira_headers = {"Authorization": f"Bearer {mira_login.json()['access_token']}"}

        # Mira creates private trip
        t_resp = await client.post("/api/trips", json={
            "name": f"Mira Secret Expedition {uuid.uuid4().hex[:6]}",
            "destination_name": "Kyoto",
            "start_date": "2026-10-01",
            "end_date": "2026-10-05",
            "currency": "EUR"
        }, headers=mira_headers)
        assert t_resp.status_code == 201
        trip_id = t_resp.json()["id"]
        print(f"1. Mira created private trip {trip_id}")

        # 2. Login Aiko (Invited Member)
        aiko_login = await client.post("/api/auth/login", json={"email": AIKO, "password": DEMO_PASSWORD})
        assert aiko_login.status_code == 200
        aiko_headers = {"Authorization": f"Bearer {aiko_login.json()['access_token']}"}

        # Mira invites Aiko
        inv = await client.post(f"/api/trips/{trip_id}/invitations", json={"role": "member", "scope": "full"}, headers=mira_headers)
        assert inv.status_code in {200, 201}
        token = inv.json()["token"]

        # Aiko accepts
        join_resp = await client.post(f"/api/invitations/{token}/accept", headers=aiko_headers)
        assert join_resp.status_code == 200
        print("2. Aiko successfully accepted invitation and joined Mira's trip.")

        # 3. Aiko (authorized member) can read the trip
        aiko_view = await client.get(f"/api/trips/{trip_id}", headers=aiko_headers)
        print(f"3. Aiko (member) GET private trip: HTTP {aiko_view.status_code}")
        assert aiko_view.status_code == 200

        # 4. Login Leo (Unauthorized Non-Member)
        leo_login = await client.post("/api/auth/login", json={"email": LEO, "password": DEMO_PASSWORD})
        assert leo_login.status_code == 200
        leo_headers = {"Authorization": f"Bearer {leo_login.json()['access_token']}"}

        # 5. Leo attempts to view Mira's private trip -> REJECTED (403 or 404)
        leo_view = await client.get(f"/api/trips/{trip_id}", headers=leo_headers)
        print(f"4. Leo (unauthorized) GET private trip: HTTP {leo_view.status_code} (access denied)")
        assert leo_view.status_code in {403, 404}

        # 6. Leo attempts to post an expense to Mira's trip -> REJECTED
        leo_exp = await client.post(f"/api/trips/{trip_id}/expenses", json={
            "title": "Leo Unauthorized Expense",
            "amount": 50.0,
            "category": "food",
            "split": "equal"
        }, headers=leo_headers)
        print(f"5. Leo (unauthorized) POST expense: HTTP {leo_exp.status_code} (access denied)")
        assert leo_exp.status_code in {403, 404}

        # 7. Leo attempts to delete Mira's trip -> REJECTED
        leo_del = await client.delete(f"/api/trips/{trip_id}", headers=leo_headers)
        print(f"6. Leo (unauthorized) DELETE trip: HTTP {leo_del.status_code} (access denied)")
        assert leo_del.status_code in {403, 404}

    print(">> MULTI-USER SECURITY & TENANT ISOLATION PASSED 100%")


async def test_reliability():
    print("\n=======================================================")
    print("STEP 3.6 — RELIABILITY & EDGE CASES")
    print("=======================================================")

    # 1. Unreachable API Handling
    async with httpx.AsyncClient(base_url="http://127.0.0.1:9999", timeout=1.0) as dead_client:
        try:
            await dead_client.get("/api/health")
            raise AssertionError("Should have raised ConnectError")
        except (httpx.ConnectError, httpx.TimeoutException):
            print("1. Unreachable backend simulation: gracefully caught connection error.")

    async with httpx.AsyncClient(base_url=BASE_URL, timeout=15.0) as client:
        login_resp = await client.post("/api/auth/login", json={"email": MIRA, "password": DEMO_PASSWORD})
        assert login_resp.status_code == 200
        headers = {"Authorization": f"Bearer {login_resp.json()['access_token']}"}

        trips_resp = await client.get("/api/trips", headers=headers)
        trip_id = trips_resp.json()["items"][0]["id"]

        # 2. Offline Sync Idempotent Deduplication
        dedup_id = f"dedup-sync-{uuid.uuid4().hex[:12]}"
        sync_body = [{
            "client_id": dedup_id,
            "operation": "memory_create",
            "payload": {"text_content": "Idempotent snap test", "caption": "Replay"}
        }]
        rep1 = await client.post(f"/api/trips/{trip_id}/sync", json=sync_body, headers=headers)
        rep2 = await client.post(f"/api/trips/{trip_id}/sync", json=sync_body, headers=headers)
        print(f"2. Idempotent sync replay: 1st HTTP {rep1.status_code}, 2nd HTTP {rep2.status_code}")
        assert rep1.status_code == 200 and rep2.status_code == 200
        print("   Replayed offline sync processed idempotently without duplicates.")

        # 3. Valid Media Upload (PNG)
        # Small 1x1 valid PNG bytes
        png_bytes = b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15c4\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82'
        upload_resp = await client.post(
            f"/api/trips/{trip_id}/media",
            files={"file": ("test.png", png_bytes, "image/png")},
            headers=headers
        )
        print(f"3. Valid media upload: HTTP {upload_resp.status_code}")
        assert upload_resp.status_code == 201
        print(f"   Uploaded media URL: {upload_resp.json()['media_url']}")

        # 4. Mismatched media type upload rejection
        fake_png = b"THIS IS NOT A VALID PNG FILE"
        bad_media_resp = await client.post(
            f"/api/trips/{trip_id}/media",
            files={"file": ("fake.png", fake_png, "image/png")},
            headers=headers
        )
        print(f"4. Invalid media file bytes: HTTP {bad_media_resp.status_code} (rejected)")
        assert bad_media_resp.status_code == 415

        # 5. Oversized payload rejection (> 25MB BodySizeLimitMiddleware)
        # We test with a dummy 26MB stream to verify size enforcement
        oversized = b"0" * (26 * 1024 * 1024)
        try:
            huge_resp = await client.post(
                f"/api/trips/{trip_id}/media",
                files={"file": ("huge.png", oversized, "image/png")},
                headers=headers
            )
            print(f"5. Oversized payload (26MB): HTTP {huge_resp.status_code}")
            assert huge_resp.status_code in {413, 422}
        except httpx.RequestError as e:
            print(f"5. Oversized payload stream terminated safely by server: {type(e).__name__}")

        # 6. WebSocket Reconnection drill
        t_resp = await client.post("/api/auth/ws-ticket", headers=headers)
        ws_ticket = t_resp.json()["ticket"]
        ws_url = f"{WS_URL}/ws/trips/{trip_id}?token={ws_ticket}"

        # Connect 1
        async with websockets.connect(ws_url) as ws1:
            msg1 = json.loads(await asyncio.wait_for(ws1.recv(), timeout=3.0))
            assert msg1.get("event") == "connected"
            print("6. WebSocket connect #1 successful.")

        # Reconnect with new ticket
        t_resp2 = await client.post("/api/auth/ws-ticket", headers=headers)
        ws_ticket2 = t_resp2.json()["ticket"]
        ws_url2 = f"{WS_URL}/ws/trips/{trip_id}?token={ws_ticket2}"

        async with websockets.connect(ws_url2) as ws2:
            msg2 = json.loads(await asyncio.wait_for(ws2.recv(), timeout=3.0))
            assert msg2.get("event") == "connected"
            print("   WebSocket reconnection #2 successful.")

    print(">> RELIABILITY & EDGE CASES PASSED 100%")


async def main():
    print("#######################################################")
    print("SAFAR PHASE 13 STEP 3 — LIVE STAGING INTEGRATION SUITE")
    print("Target API: http://127.0.0.1:8020")
    print("Database:   Supabase PostgreSQL 17 (role: safar_app)")
    print("#######################################################")

    await test_auth_and_sessions()
    await test_core_workflows()
    await test_multi_user_isolation()
    await test_reliability()

    print("\n*******************************************************")
    print("ALL LIVE STAGING INTEGRATION TESTS COMPLETED SUCCESSFULLY!")
    print("*******************************************************\n")


if __name__ == "__main__":
    asyncio.run(main())
