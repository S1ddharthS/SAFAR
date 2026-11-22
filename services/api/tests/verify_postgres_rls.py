import os
import secrets
from datetime import date
from urllib.parse import urlparse, urlunparse
import psycopg
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.core.config import settings
from app.db.context import set_user_context, system_context
from app.models.models import Trip, TripMember, User

def main():
    import re
    from pathlib import Path

    staging_env = Path("C:/Users/siddharth/Desktop/SAFAR/.env.staging")
    app_pwd = "safar_app_sec_d09eb115a3ef5fcdc84dcdebec069668"
    if staging_env.exists():
        content = staging_env.read_text(encoding="utf-8")
        m = re.search(r"DATABASE_URL=postgresql\+psycopg://safar_app:([^@]+)@", content)
        if m:
            app_pwd = m.group(1)

    admin_conn_str = "postgresql://postgres.qekbbbkmhpvdktctfgow:safarisatravellingapp@aws-0-ap-south-1.pooler.supabase.com:5432/postgres?sslmode=require"

    # 1. Admin setup: ensure non-owner safar_app role exists and has permissions
    with psycopg.connect(admin_conn_str) as conn:
        conn.autocommit = True
        with conn.cursor() as cur:
            cur.execute("SELECT 1 FROM pg_roles WHERE rolname = 'safar_app';")
            if not cur.fetchone():
                cur.execute(f"CREATE ROLE safar_app LOGIN PASSWORD '{app_pwd}' NOBYPASSRLS;")
            else:
                cur.execute(f"ALTER ROLE safar_app WITH PASSWORD '{app_pwd}';")
            
            cur.execute("GRANT USAGE ON SCHEMA public TO safar_app;")
            cur.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO safar_app;")
            cur.execute("GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO safar_app;")
            print("1. safar_app non-owner role configured with NOBYPASSRLS.")

    # 2. Configure SQLAlchemy engine connected strictly as non-owner safar_app
    app_db_url = f"postgresql+psycopg://safar_app.qekbbbkmhpvdktctfgow:{app_pwd}@aws-0-ap-south-1.pooler.supabase.com:5432/postgres?sslmode=require"

    app_engine = create_engine(app_db_url, pool_pre_ping=True)
    AppSession = sessionmaker(bind=app_engine, autocommit=False, autoflush=False)

    user_a_id = "test_rls_user_a_" + secrets.token_hex(4)
    user_b_id = "test_rls_user_b_" + secrets.token_hex(4)
    trip_a_id = "test_rls_trip_a_" + secrets.token_hex(4)

    # 3. Test Anonymous Read
    with AppSession() as db:
        anon_trips = db.query(Trip).all()
        print(f"2. Anonymous query (no GUC context): {len(anon_trips)} trips visible (expected 0).")
        assert len(anon_trips) == 0, "Anonymous user must see 0 trips under RLS"

    # 4. Provision User A, User B, Trip A using system context
    with AppSession() as db:
        with system_context(db):
            user_a = User(
                id=user_a_id,
                email=f"{user_a_id}@safar.test",
                password_hash="test_hash",
                display_name="User A",
            )
            user_b = User(
                id=user_b_id,
                email=f"{user_b_id}@safar.test",
                password_hash="test_hash",
                display_name="User B",
            )
            trip_a = Trip(
                id=trip_a_id,
                name="Secret Journey A",
                destination_name="Paris",
                start_date=date(2026, 6, 1),
                end_date=date(2026, 6, 5),
                created_by=user_a_id,
                privacy="private",
            )
            member_a = TripMember(
                trip_id=trip_a_id,
                user_id=user_a_id,
                role="owner",
                status="active",
            )
            db.add_all([user_a, user_b])
            db.flush()
            db.add_all([trip_a, member_a])
            db.commit()
            print("3. Provisioned test users and private Trip A under system context.")

    # 5. User A authorized access
    with AppSession() as db:
        set_user_context(db, user_a_id)
        user_a_trips = db.query(Trip).filter(Trip.id == trip_a_id).all()
        print(f"4. User A query own trip: {len(user_a_trips)} trip(s) returned (expected 1).")
        assert len(user_a_trips) == 1
        assert user_a_trips[0].name == "Secret Journey A"

    # 6. User B unauthorized cross-tenant operations
    with AppSession() as db:
        set_user_context(db, user_b_id)
        
        # Cross-tenant SELECT
        user_b_read = db.query(Trip).filter(Trip.id == trip_a_id).all()
        print(f"5. User B cross-tenant SELECT: {len(user_b_read)} row(s) returned (expected 0).")
        assert len(user_b_read) == 0, "PostgreSQL RLS must reject cross-tenant reads"

        # Cross-tenant UPDATE
        updated_rows = db.query(Trip).filter(Trip.id == trip_a_id).update({"name": "Hacked by User B"})
        db.commit()
        print(f"6. User B cross-tenant UPDATE: {updated_rows} row(s) updated (expected 0).")
        assert updated_rows == 0, "PostgreSQL RLS must reject cross-tenant updates"

        # Cross-tenant DELETE
        deleted_rows = db.query(Trip).filter(Trip.id == trip_a_id).delete()
        db.commit()
        print(f"7. User B cross-tenant DELETE: {deleted_rows} row(s) deleted (expected 0).")
        assert deleted_rows == 0, "PostgreSQL RLS must reject cross-tenant deletes"

    print("POSTGRESQL RLS MULTI-TENANT ISOLATION: ALL ASSERTIONS PASSED!")

    # 7. Cleanup test data
    with AppSession() as db:
        with system_context(db):
            db.query(TripMember).filter(TripMember.trip_id == trip_a_id).delete()
            db.query(Trip).filter(Trip.id == trip_a_id).delete()
            db.query(User).filter(User.id.in_([user_a_id, user_b_id])).delete()
            db.commit()
            print("8. Test data cleaned up successfully.")

if __name__ == '__main__':
    main()
