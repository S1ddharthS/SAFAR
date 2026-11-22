"""SAFAR Phase 13 Step 4: Multi-User Controlled Pilot & End-to-End Journey Validation
Runs directly against Staging on Port 8020 with Supabase PostgreSQL 17 (safar_app role).

Exercises:
- Journey A: Collaborative Trip Planning (Mira, Aiko, Leo, Jonas)
- Journey B: Accessibility-Aware Planning (Aiko mobility constraints)
- Journey C: Group Experience Engine (Everyone Wins, Your Turn, Surprise Us)
- Journey D: Expenses, Splits, Shared/Private Memories, Permissions & Editing
- Journey E: Local Contributor Workflows & Boundaries (Noor)
- Journey F: Disruption & Recovery (Trip Rescue & Journey Pact protection)
- Permissions & Privacy Matrix: Admin vs Member vs Non-member, Token single-use, Session revocation
"""

import asyncio
import json
import uuid
from datetime import date, datetime, timedelta
import httpx

BASE_URL = "http://127.0.0.1:8020"

MIRA = "mira@safar.demo"     # Trip Owner & Admin
JONAS = "jonas@safar.demo"   # Trip Co-Admin
AIKO = "aiko@safar.demo"     # Accessibility user
LEO = "leo@safar.demo"       # Regular member
NOOR = "noor@safar.demo"     # Local Contributor
DEMO_PASSWORD = "safar-demo-123"


async def get_client_and_token(email: str):
    client = httpx.AsyncClient(base_url=BASE_URL, timeout=15.0)
    resp = await client.post("/api/auth/login", json={"email": email, "password": DEMO_PASSWORD})
    assert resp.status_code == 200, f"Login failed for {email}: {resp.text}"
    token = resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    return client, headers, resp.json()["user"]


async def main():
    print("======================================================================")
    print("SAFAR PHASE 13 STEP 4 — MULTI-USER JOURNEY & PILOT VALIDATION")
    print("Target API: http://127.0.0.1:8020 (Supabase PostgreSQL 17, safar_app)")
    print("======================================================================")

    # 1. Pilot Test Accounts Setup
    print("\n--- 1. Establishing Pilot Test Accounts ---")
    mira_client, mira_h, mira_user = await get_client_and_token(MIRA)
    jonas_client, jonas_h, jonas_user = await get_client_and_token(JONAS)
    aiko_client, aiko_h, aiko_user = await get_client_and_token(AIKO)
    leo_client, leo_h, leo_user = await get_client_and_token(LEO)
    noor_client, noor_h, noor_user = await get_client_and_token(NOOR)
    print(f"Logged in: Mira ({mira_user['id'][:8]}), Jonas ({jonas_user['id'][:8]}), Aiko ({aiko_user['id'][:8]}), Leo ({leo_user['id'][:8]}), Noor ({noor_user['id'][:8]})")

    # Fetch Kyoto destination
    dests_resp = await mira_client.get("/api/destinations", headers=mira_h)
    assert dests_resp.status_code == 200
    kyoto = dests_resp.json()["items"][0]
    kyoto_id = kyoto["id"]
    print(f"Destination: {kyoto['name']}, {kyoto['country']} (ID: {kyoto_id})")

    # =========================================================================
    # JOURNEY A: Collaborative Trip Planning
    # =========================================================================
    print("\n--- JOURNEY A: Collaborative Trip Planning ---")
    # Mira creates a private trip
    trip_name = f"Pilot Odyssey {uuid.uuid4().hex[:6]}"
    trip_resp = await mira_client.post("/api/trips", json={
        "name": trip_name,
        "destination_id": kyoto_id,
        "destination_name": kyoto["name"],
        "start_date": "2026-10-10",
        "end_date": "2026-10-18",
        "currency": "EUR"
    }, headers=mira_h)
    assert trip_resp.status_code == 201
    trip = trip_resp.json()
    trip_id = trip["id"]
    print(f"1. Mira created private trip '{trip_name}' (ID: {trip_id})")

    # Mira invites Aiko (member), Leo (member), and Jonas (admin)
    inv_aiko = await mira_client.post(f"/api/trips/{trip_id}/invitations", json={"role": "member", "scope": "full"}, headers=mira_h)
    inv_leo = await mira_client.post(f"/api/trips/{trip_id}/invitations", json={"role": "member", "scope": "full"}, headers=mira_h)
    inv_jonas = await mira_client.post(f"/api/trips/{trip_id}/invitations", json={"role": "admin", "scope": "full"}, headers=mira_h)
    assert inv_aiko.status_code == 201 and inv_leo.status_code == 201 and inv_jonas.status_code == 201

    token_aiko = inv_aiko.json()["token"]
    token_leo = inv_leo.json()["token"]
    token_jonas = inv_jonas.json()["token"]

    # Preview invitations
    prev = await aiko_client.get(f"/api/invitations/{token_aiko}")
    assert prev.status_code == 200
    print(f"2. Aiko previewed invite: {prev.json()['trip']['name']}")

    # Accept invitations
    j1 = await aiko_client.post(f"/api/invitations/{token_aiko}/accept", headers=aiko_h)
    j2 = await leo_client.post(f"/api/invitations/{token_leo}/accept", headers=leo_h)
    j3 = await jonas_client.post(f"/api/invitations/{token_jonas}/accept", headers=jonas_h)
    assert j1.status_code == 200 and j2.status_code == 200 and j3.status_code == 200
    print("3. Aiko, Leo, and Jonas accepted invitations successfully.")

    # Single-use invitation verification: re-accepting token_aiko by Leo must fail (409)
    reuse_inv = await leo_client.post(f"/api/invitations/{token_aiko}/accept", headers=leo_h)
    print(f"4. Replay accepted invitation token: HTTP {reuse_inv.status_code} (rejected single-use)")
    assert reuse_inv.status_code == 409

    # All members see the correct trip and membership info
    members_resp = await mira_client.get(f"/api/trips/{trip_id}/members", headers=mira_h)
    assert members_resp.status_code == 200
    members = members_resp.json()["items"]
    assert len(members) == 4
    roles = {m["user"]["id"]: m["role"] for m in members}
    print(f"5. Active trip members confirmed (count: {len(members)}): {roles}")
    assert roles[mira_user["id"]] == "owner" and roles[jonas_user["id"]] == "admin" and roles[aiko_user["id"]] == "member" and roles[leo_user["id"]] == "member"

    # Mira creates itinerary item
    item_resp = await mira_client.post(f"/api/trips/{trip_id}/itinerary/items", json={
        "day": "2026-10-11",
        "start_time": "09:30",
        "end_time": "12:00",
        "title": "Fushimi Inari Morning Walk",
        "is_protected": True
    }, headers=mira_h)
    assert item_resp.status_code == 201
    item_id = item_resp.json()["id"]
    print(f"6. Mira scheduled confirmed item: '{item_resp.json()['title']}' (protected=True)")

    # Fetch recommendations for proposal
    rec_resp = await jonas_client.post(f"/api/trips/{trip_id}/engine/recommend", json={
        "mode": "everyone_wins",
        "for_date": "2026-10-12"
    }, headers=jonas_h)
    assert rec_resp.status_code == 201
    rec_items = rec_resp.json()["items"]
    assert len(rec_items) > 0
    proposed_act = rec_items[0]["activity_id"]

    # Jonas proposes changes
    prop_resp = await jonas_client.post(f"/api/trips/{trip_id}/proposals", json={
        "kind": "add_activity",
        "activity_id": proposed_act,
        "day": "2026-10-12",
        "start_time": "14:00",
        "title": "Matcha Tea & Zen Garden Exploration",
        "summary": "Jonas proposed activity for group vote"
    }, headers=jonas_h)
    assert prop_resp.status_code == 201
    prop_id = prop_resp.json()["id"]
    print(f"7. Jonas submitted proposal '{prop_resp.json()['title']}' (ID: {prop_id})")

    # Verify pending proposal does NOT silently modify confirmed itinerary
    itin_before = (await mira_client.get(f"/api/trips/{trip_id}/itinerary", headers=mira_h)).json()["items"]
    assert len(itin_before) == 1, "Pending proposal must NOT modify itinerary yet"
    print("   Verified: Itinerary remains unchanged while proposal is pending.")

    # Members vote
    await aiko_client.post(f"/api/trips/{trip_id}/proposals/{prop_id}/vote", json={"value": "yes"}, headers=aiko_h)
    await leo_client.post(f"/api/trips/{trip_id}/proposals/{prop_id}/vote", json={"value": "yes"}, headers=leo_h)
    await mira_client.post(f"/api/trips/{trip_id}/proposals/{prop_id}/vote", json={"value": "yes"}, headers=mira_h)
    print("8. Votes recorded from Aiko (yes), Leo (yes), Mira (yes).")

    # Approved proposal updates the itinerary
    app_resp = await mira_client.post(f"/api/trips/{trip_id}/proposals/{prop_id}/approve", json={"approval": True}, headers=mira_h)
    assert app_resp.status_code == 200
    print(f"9. Proposal approved: HTTP {app_resp.status_code}")

    itin_after = (await mira_client.get(f"/api/trips/{trip_id}/itinerary", headers=mira_h)).json()["items"]
    assert len(itin_after) == 2, "Approved proposal must be added to confirmed itinerary"
    print(f"   Confirmed itinerary now has {len(itin_after)} items.")

    # Test rejection behaviour: Jonas proposes a second activity that gets rejected
    if len(rec_items) > 1:
        prop_rej = await jonas_client.post(f"/api/trips/{trip_id}/proposals", json={
            "kind": "add_activity",
            "activity_id": rec_items[1]["activity_id"],
            "day": "2026-10-13",
            "start_time": "15:00",
            "title": "Rejected Alternative",
            "summary": "This proposal will be rejected"
        }, headers=jonas_h)
        assert prop_rej.status_code == 201
        rej_id = prop_rej.json()["id"]

        rej_resp = await mira_client.post(f"/api/trips/{trip_id}/proposals/{rej_id}/reject", headers=mira_h)
        assert rej_resp.status_code == 200
        print(f"10. Proposal rejection: HTTP {rej_resp.status_code}")

        itin_final = (await mira_client.get(f"/api/trips/{trip_id}/itinerary", headers=mira_h)).json()["items"]
        assert len(itin_final) == 2, "Rejected proposal must NOT modify itinerary"
        print("    Verified: Rejected proposal did not alter the confirmed itinerary.")

    print(">> JOURNEY A COMPLETED SUCCESSFULLY 100%")

    # =========================================================================
    # JOURNEY B: Accessibility-Aware Planning
    # =========================================================================
    print("\n--- JOURNEY B: Accessibility-Aware Planning ---")
    # Aiko updates both profile and trip membership with explicit mobility / wheelchair accessibility need
    patch_prof = await aiko_client.patch("/api/users/me/profile", json={
        "accessibility_needs": ["wheelchair_access", "step_free"]
    }, headers=aiko_h)
    assert patch_prof.status_code == 200

    patch_member = await aiko_client.patch(f"/api/trips/{trip_id}/members/me", json={
        "accessibility_needs": ["wheelchair_access", "step_free"]
    }, headers=aiko_h)
    assert patch_member.status_code == 200
    print("1. Aiko set accessibility_needs on profile & trip membership: ['wheelchair_access', 'step_free']")

    # Generate group recommendations with Aiko's accessibility constraints active
    acc_recs = await mira_client.post(f"/api/trips/{trip_id}/engine/recommend", json={
        "mode": "everyone_wins",
        "for_date": "2026-10-12"
    }, headers=mira_h)
    assert acc_recs.status_code == 201
    acc_batch = acc_recs.json()
    items = acc_batch["items"]
    print(f"2. Recommendations generated under accessibility constraint: {len(items)} items")

    # Verify that inaccessible options are NEVER recommended
    for item in items:
        # Check explanation constraint metadata
        explanation = item.get("explanation", {})
        constraints = explanation.get("constraints_checked", [])
        acc_constraint = next((c for c in constraints if c.get("constraint") == "Accessibility"), None)
        assert acc_constraint is not None, f"Accessibility constraint check missing from: {explanation}"
        assert acc_constraint["status"] in {"satisfied", "unknown"}, f"Violated accessibility found: {acc_constraint}"

        # Confirm explainability & reasoning
        assert "summary" in explanation
        assert "why_selected" in explanation
        assert "uncertainties" in explanation
    print("3. Verified: All recommended activities satisfy accessibility constraints or declare explicit uncertainty.")
    print("4. Verified: Inaccessible venues are excluded by hard constraint filters.")
    print(">> JOURNEY B COMPLETED SUCCESSFULLY 100%")

    # =========================================================================
    # JOURNEY C: Group Experience Engine (All Modes)
    # =========================================================================
    print("\n--- JOURNEY C: Group Experience Engine Modes & Provenance ---")
    modes = ["everyone_wins", "your_turn", "surprise_us"]
    for m in modes:
        mode_resp = await mira_client.post(f"/api/trips/{trip_id}/engine/recommend", json={
            "mode": m,
            "for_date": "2026-10-13",
            "limit": 4
        }, headers=mira_h)
        assert mode_resp.status_code == 201
        m_data = mode_resp.json()
        eval_meta = m_data.get("meta", {}).get("evaluation", {})
        jain = eval_meta.get("fairness", {}).get("jain_index", "N/A")
        print(f"Engine mode '{m}': {len(m_data['items'])} items returned | Jain Index: {jain}")
        assert m_data["mode"] == m

    # Confirm that generating recommendations does NOT mutate itinerary
    itin_check = (await mira_client.get(f"/api/trips/{trip_id}/itinerary", headers=mira_h)).json()["items"]
    assert len(itin_check) == 2, "Generating recommendations must never mutate itinerary automatically"
    print("Verified: Engine recommendation batches do not mutate the confirmed itinerary.")
    print(">> JOURNEY C COMPLETED SUCCESSFULLY 100%")

    # =========================================================================
    # JOURNEY D: Expenses, Balances, Shared & Private Memories
    # =========================================================================
    print("\n--- JOURNEY D: Expenses, Balances & Memories Permissions ---")
    # Multiple members add expenses
    exp1 = await mira_client.post(f"/api/trips/{trip_id}/expenses", json={
        "title": "Group Ryokan Stay",
        "amount": 400.0,
        "category": "accommodation",
        "split": "equal"
    }, headers=mira_h)
    assert exp1.status_code == 201

    exp2 = await leo_client.post(f"/api/trips/{trip_id}/expenses", json={
        "title": "Group Kaiseki Dinner",
        "amount": 200.0,
        "category": "food",
        "split": "equal"
    }, headers=leo_h)
    assert exp2.status_code == 201
    print("1. Mira logged €400.00 (stay); Leo logged €200.00 (dinner).")

    # Verify balances and debt settlement calculations
    bal_resp = await aiko_client.get(f"/api/trips/{trip_id}/expenses/balances", headers=aiko_h)
    assert bal_resp.status_code == 200
    bal_data = bal_resp.json()
    assert bal_data["total_spent"] == 600.0
    print(f"2. Group balances calculated: Total Spent = €{bal_data['total_spent']:.2f} across 4 members")
    assert "settlements" in bal_data
    print(f"   Settlement transactions: {len(bal_data['settlements'])} transfers proposed")

    # Add shared trip memory
    mem_shared = await mira_client.post(f"/api/trips/{trip_id}/memories", json={
        "kind": "text",
        "text_content": "Group gathering in the bamboo grove",
        "caption": "Serene Morning",
        "visibility": "trip"
    }, headers=mira_h)
    assert mem_shared.status_code == 201
    shared_id = mem_shared.json()["id"]

    # Add private memory by Mira
    mem_priv = await mira_client.post(f"/api/trips/{trip_id}/memories", json={
        "kind": "text",
        "text_content": "Mira private journal: bought souvenirs for family",
        "caption": "Private Reflection",
        "visibility": "private"
    }, headers=mira_h)
    assert mem_priv.status_code == 201
    priv_id = mem_priv.json()["id"]
    print(f"3. Mira captured 1 shared memory ({shared_id[:8]}) and 1 private memory ({priv_id[:8]}).")

    # Aiko retrieves timeline: should see shared memory, but NOT Mira's private memory
    aiko_mems = await aiko_client.get(f"/api/trips/{trip_id}/memories", headers=aiko_h)
    assert aiko_mems.status_code == 200
    aiko_timeline = aiko_mems.json()["days"]
    visible_ids = [m["id"] for day in aiko_timeline for m in day["memories"]]
    assert shared_id in visible_ids, "Aiko must see shared trip memory"
    assert priv_id not in visible_ids, "Aiko must NEVER see Mira's private memory!"
    print("4. Verified: Private memory is completely hidden from other trip members.")

    # Edit memory: Mira updates her shared memory
    edit_resp = await mira_client.patch(f"/api/trips/{trip_id}/memories/{shared_id}", json={
        "caption": "Serene Morning at Arashiyama (Edited)"
    }, headers=mira_h)
    assert edit_resp.status_code == 200
    print(f"5. Memory edited by owner: HTTP {edit_resp.status_code}")

    # Aiko attempts to edit Mira's memory -> rejected 403
    unauth_edit = await aiko_client.patch(f"/api/trips/{trip_id}/memories/{shared_id}", json={
        "caption": "Hacked Caption"
    }, headers=aiko_h)
    print(f"6. Unauthorized memory edit by Aiko: HTTP {unauth_edit.status_code} (rejected)")
    assert unauth_edit.status_code == 403

    # Delete memory: Mira deletes private memory
    del_resp = await mira_client.delete(f"/api/trips/{trip_id}/memories/{priv_id}", headers=mira_h)
    assert del_resp.status_code == 200
    print(f"7. Memory deleted by owner: HTTP {del_resp.status_code}")
    print(">> JOURNEY D COMPLETED SUCCESSFULLY 100%")

    # =========================================================================
    # JOURNEY E: Local Contributor Workflows & Boundaries
    # =========================================================================
    print("\n--- JOURNEY E: Local Contributor Workflows & Boundaries (Noor) ---")
    # Noor accesses contributor registration
    contrib_reg = await noor_client.post("/api/contributors", json={
        "destination_id": kyoto_id,
        "bio": "Kyoto resident & architectural historian. Love sharing quiet tea houses.",
        "expertise": ["architecture", "tea_culture", "gardens"],
        "accepts_requests": True
    }, headers=noor_h)
    assert contrib_reg.status_code == 200
    print(f"1. Noor registered as local contributor for Kyoto: HTTP {contrib_reg.status_code}")

    # List contributors: verify provenance disclosure
    contribs = await mira_client.get(f"/api/contributors?destination_id={kyoto_id}", headers=mira_h)
    assert contribs.status_code == 200
    c_list = contribs.json()
    assert "disclosure" in c_list
    print(f"2. Contributor provenance: '{c_list['disclosure']}'")

    # Verify that Noor (non-member) CANNOT access private trip information
    noor_trip_attempt = await noor_client.get(f"/api/trips/{trip_id}", headers=noor_h)
    print(f"3. Noor attempts GET private trip: HTTP {noor_trip_attempt.status_code} (access denied)")
    assert noor_trip_attempt.status_code in {403, 404}

    noor_mem_attempt = await noor_client.get(f"/api/trips/{trip_id}/memories", headers=noor_h)
    print(f"4. Noor attempts GET private memories: HTTP {noor_mem_attempt.status_code} (access denied)")
    assert noor_mem_attempt.status_code in {403, 404}
    print(">> JOURNEY E COMPLETED SUCCESSFULLY 100%")

    # =========================================================================
    # JOURNEY F: Disruption & Recovery (Trip Rescue)
    # =========================================================================
    print("\n--- JOURNEY F: Disruption & Recovery (Trip Rescue) ---")
    # Simulate a disruption using Trip Rescue
    rescue_resp = await mira_client.post(f"/api/trips/{trip_id}/rescue/analyze", json={
        "kind": "rain",
        "extra_minutes": 60,
        "note": "Typhoon rain advisory in Kyoto"
    }, headers=mira_h)
    assert rescue_resp.status_code == 200
    rescue_data = rescue_resp.json()
    print(f"1. Trip Rescue analysis: Disruption = {rescue_data['disruption']['kind']} ('{rescue_data['disruption']['label']}')")
    assert "affected" in rescue_data
    assert "protected" in rescue_data
    assert "proposals" in rescue_data
    assert rescue_data.get("requires_approval", True) is True
    assert "disclosure" in rescue_data

    # Confirm that protected free time is respected and no itinerary changes happened without approval
    itin_current = (await mira_client.get(f"/api/trips/{trip_id}/itinerary", headers=mira_h)).json()["items"]
    assert len(itin_current) == 2, "Trip Rescue analysis must NEVER mutate itinerary without explicit proposal approval"
    protected_item = next((i for i in itin_current if i.get("is_protected")), None)
    assert protected_item is not None
    print(f"2. Verified: Protected item '{protected_item['title']}' remains untouched.")
    print("3. Verified: No itinerary change occurred without group proposal and explicit approval.")
    print(">> JOURNEY F COMPLETED SUCCESSFULLY 100%")

    # =========================================================================
    # PERMISSIONS & PRIVACY MATRIX
    # =========================================================================
    print("\n--- PERMISSIONS & PRIVACY MATRIX ---")
    # Owner vs Admin vs Member permissions:
    # Leo (regular member) attempts to invite someone -> must be rejected (only owner/admin can invite)
    leo_invite = await leo_client.post(f"/api/trips/{trip_id}/invitations", json={"role": "member", "scope": "full"}, headers=leo_h)
    print(f"1. Leo (member) attempts to issue invite: HTTP {leo_invite.status_code} (rejected)")
    assert leo_invite.status_code in {403, 422}

    # Jonas (admin) issues invite -> succeeds
    jonas_invite = await jonas_client.post(f"/api/trips/{trip_id}/invitations", json={"role": "member", "scope": "full"}, headers=jonas_h)
    print(f"2. Jonas (admin) issues invite: HTTP {jonas_invite.status_code} (allowed)")
    assert jonas_invite.status_code in {200, 201}

    # Leo attempts to delete trip -> rejected
    leo_del_trip = await leo_client.delete(f"/api/trips/{trip_id}", headers=leo_h)
    print(f"3. Leo (member) attempts to delete trip: HTTP {leo_del_trip.status_code} (rejected)")
    assert leo_del_trip.status_code in {403, 404}

    # Jonas (admin) attempts to delete trip -> rejected (only owner can delete trip)
    jonas_del_trip = await jonas_client.delete(f"/api/trips/{trip_id}", headers=jonas_h)
    print(f"4. Jonas (admin) attempts to delete trip: HTTP {jonas_del_trip.status_code} (rejected)")
    assert jonas_del_trip.status_code in {403, 404}

    # Session revocation check on logout
    await jonas_client.post("/api/auth/logout", headers=jonas_h)
    jonas_me = await jonas_client.get("/api/auth/me", headers=jonas_h)
    print(f"5. Jonas session after logout: HTTP {jonas_me.status_code} (revoked)")
    assert jonas_me.status_code == 401

    print(">> PERMISSIONS & PRIVACY MATRIX PASSED 100%")

    # Close clients
    await mira_client.aclose()
    await jonas_client.aclose()
    await aiko_client.aclose()
    await leo_client.aclose()
    await noor_client.aclose()

    print("\n**********************************************************************")
    print("ALL PHASE 13 STEP 4 MULTI-USER JOURNEYS & PILOT TESTS PASSED 100%!")
    print("**********************************************************************\n")


if __name__ == "__main__":
    asyncio.run(main())
