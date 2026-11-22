import os
import importlib
from starlette.testclient import TestClient

from app.core import config
# Ensure staging config is freshly loaded
os.environ["SAFAR_ENV_FILE"] = ".env.staging"
importlib.reload(config)

from app.core.config import settings
from app.db.session import engine, SessionLocal
from app.db.context import system_context
from app.main import app
from app.core.security import create_access_token, hash_password
from app.models.models import User, Trip, TripMember

def main():
    print("--- TASK 1: APPLICATION DATABASE ROLE & API-LEVEL RLS VERIFICATION ---")

    # 1. Inspect live connection role
    with engine.connect() as conn:
        result = conn.exec_driver_sql("SELECT current_user, session_user;").fetchone()
        current_u, session_u = result[0], result[1]
        print(f"1. Database connected as: current_user='{current_u}', session_user='{session_u}'")
        assert current_u == "safar_app", f"Expected safar_app, got {current_u}"

        # 2. Verify role attributes (NOSUPERUSER, NOBYPASSRLS)
        role_attrs = conn.exec_driver_sql("""
            SELECT rolsuper, rolbypassrls, rolcreatedb, rolcreaterole 
            FROM pg_roles 
            WHERE rolname = current_user;
        """).fetchone()
        is_super, bypass_rls, create_db, create_role = role_attrs
        print(f"2. Role attributes: SUPERUSER={is_super}, BYPASSRLS={bypass_rls}, CREATEDB={create_db}, CREATEROLE={create_role}")
        assert not is_super, "safar_app must be NOSUPERUSER"
        assert not bypass_rls, "safar_app must be NOBYPASSRLS"

        # 3. Verify safar_app does not own protected domain tables
        owned_tables = conn.exec_driver_sql("""
            SELECT tablename, tableowner 
            FROM pg_tables 
            WHERE schemaname = 'public' AND tableowner = current_user;
        """).fetchall()
        print(f"3. Tables owned by safar_app: {len(owned_tables)} (expected 0, owned by postgres)")
        assert len(owned_tables) == 0, f"safar_app must not own domain tables! Owned: {owned_tables}"

        # 4. Verify missing tenant context fails closed
        cnt = conn.exec_driver_sql("SELECT count(*) FROM trips;").fetchone()[0]
        print(f"4. Missing tenant context query: {cnt} trips returned (fails closed).")
        assert cnt == 0, "Query with no tenant GUC must return 0 rows"

    # 5. Application-level cross-user API tests using FastAPI TestClient
    client = TestClient(app, base_url="http://localhost")

    trip_id = None
    u1_id = "api_test_user_1"
    u2_id = "api_test_user_2"
    u1_token = create_access_token(u1_id, "u1@safar.demo")
    u2_token = create_access_token(u2_id, "u2@safar.demo")

    # Seed users using system context
    with SessionLocal() as db:
        with system_context(db):
            db.merge(User(
                id=u1_id,
                email="u1@safar.demo",
                password_hash=hash_password("password123"),
                display_name="User 1",
            ))
            db.merge(User(
                id=u2_id,
                email="u2@safar.demo",
                password_hash=hash_password("password123"),
                display_name="User 2",
            ))
            db.commit()

    try:
        # User 1 creates a private trip via API
        resp_create = client.post(
            "/api/trips",
            json={
                "name": "User 1 Private Voyage",
                "destination_name": "Kyoto",
                "start_date": "2026-07-01",
                "end_date": "2026-07-10",
                "privacy": "private"
            },
            headers={"Authorization": f"Bearer {u1_token}"}
        )
        print(f"5. User 1 creates trip via API: status={resp_create.status_code}")
        assert resp_create.status_code == 201, f"Create trip failed: {resp_create.text}"
        trip_id = resp_create.json()["id"]

        # User 1 reads own trip via API
        resp_read_u1 = client.get(
            f"/api/trips/{trip_id}",
            headers={"Authorization": f"Bearer {u1_token}"}
        )
        print(f"6. User 1 reads own trip via API: status={resp_read_u1.status_code}")
        assert resp_read_u1.status_code == 200

        # User 2 attempts to read User 1's private trip via API
        resp_read_u2 = client.get(
            f"/api/trips/{trip_id}",
            headers={"Authorization": f"Bearer {u2_token}"}
        )
        print(f"7. User 2 cross-user GET attempt: status={resp_read_u2.status_code}")
        assert resp_read_u2.status_code in {403, 404}, f"User 2 should be rejected, got {resp_read_u2.status_code}"

        # User 2 attempts to update User 1's trip via API
        resp_update_u2 = client.patch(
            f"/api/trips/{trip_id}",
            json={"name": "Tampered Trip Name"},
            headers={"Authorization": f"Bearer {u2_token}"}
        )
        print(f"8. User 2 cross-user PATCH attempt: status={resp_update_u2.status_code}")
        assert resp_update_u2.status_code in {403, 404}, f"User 2 update should be rejected, got {resp_update_u2.status_code}"

        # User 2 attempts to delete User 1's trip via API
        resp_delete_u2 = client.delete(
            f"/api/trips/{trip_id}",
            headers={"Authorization": f"Bearer {u2_token}"}
        )
        print(f"9. User 2 cross-user DELETE attempt: status={resp_delete_u2.status_code}")
        assert resp_delete_u2.status_code in {403, 404}, f"User 2 delete should be rejected, got {resp_delete_u2.status_code}"

        print("--- TASK 1 COMPLETE: APPLICATION ROLE & API-LEVEL RLS FULLY VERIFIED ---")

    finally:
        # Cleanup
        with SessionLocal() as db:
            with system_context(db):
                if trip_id:
                    db.query(TripMember).filter(TripMember.trip_id == trip_id).delete()
                    db.query(Trip).filter(Trip.id == trip_id).delete()
                db.query(User).filter(User.id.in_([u1_id, u2_id])).delete()
                db.commit()
                print("10. Cleaned up API test records.")

if __name__ == "__main__":
    main()
