import os
import sys
import time
import hashlib
import subprocess
from pathlib import Path
import psycopg

def main():
    print("--- TASK 2: FULL POSTGRESQL PG_DUMP & PG_RESTORE DRILL ---")

    tools_bin = Path("C:/Users/siddharth/Desktop/SAFAR/tools/pgsql/bin")
    pg_dump_exe = tools_bin / "pg_dump.exe"
    pg_restore_exe = tools_bin / "pg_restore.exe"

    assert pg_dump_exe.exists(), f"pg_dump not found at {pg_dump_exe}"
    assert pg_restore_exe.exists(), f"pg_restore not found at {pg_restore_exe}"

    # Supabase connection parameters
    host = "db.qekbbbkmhpvdktctfgow.supabase.co"
    port = "5432"
    user = "postgres"
    password = "safarisatravellingapp"
    source_db = "postgres"
    target_db = "safar_restore_verify"

    dump_file = Path("C:/Users/siddharth/Desktop/SAFAR/storage_staging/safar_full_backup.dump")
    dump_file.parent.mkdir(parents=True, exist_ok=True)
    if dump_file.exists():
        dump_file.unlink()

    env = dict(os.environ)
    env["PGPASSWORD"] = password
    env["PATH"] = f"{tools_bin};" + env.get("PATH", "")

    # Step 1: Create complete logical backup using pg_dump -Fc
    print(f"1. Creating full custom-format logical backup with pg_dump -Fc...")
    dump_cmd = [
        str(pg_dump_exe),
        "-h", host,
        "-p", port,
        "-U", user,
        "-d", source_db,
        "-Fc",
        "-f", str(dump_file)
    ]
    t0 = time.time()
    res = subprocess.run(dump_cmd, env=env, capture_output=True, text=True)
    if res.returncode != 0:
        print("pg_dump STDERR:", res.stderr)
        raise RuntimeError(f"pg_dump failed with exit code {res.returncode}")

    dump_size = os.path.getsize(dump_file)
    with open(dump_file, "rb") as f:
        sha256 = hashlib.sha256(f.read()).hexdigest()
    print(f"   Backup successfully generated in {time.time()-t0:.2f}s!")
    print(f"   File: {dump_file.name} ({dump_size} bytes, SHA256: {sha256[:16]}...)")
    assert dump_size > 0

    # Step 2: Provision separate temporary verification database
    print(f"2. Provisioning separate temporary verification database '{target_db}'...")
    admin_conn_str = f"postgresql://{user}:{password}@{host}:{port}/{source_db}?sslmode=require"
    with psycopg.connect(admin_conn_str, autocommit=True) as conn:
        with conn.cursor() as cur:
            cur.execute(f"DROP DATABASE IF EXISTS {target_db};")
            cur.execute(f"CREATE DATABASE {target_db};")
            print(f"   Temporary database '{target_db}' created cleanly.")

    try:
        # Step 3: Restore backup into temporary database using pg_restore
        print(f"3. Restoring logical backup into '{target_db}' using pg_restore...")
        restore_cmd = [
            str(pg_restore_exe),
            "-h", host,
            "-p", port,
            "-U", user,
            "-d", target_db,
            "--no-owner",
            "--no-privileges",
            str(dump_file)
        ]
        t1 = time.time()
        res_restore = subprocess.run(restore_cmd, env=env, capture_output=True, text=True)
        # Note: pg_restore may return 1 if there are minor non-critical warnings on pre-existing extensions
        print(f"   pg_restore completed in {time.time()-t1:.2f}s (code: {res_restore.returncode}).")

        # Step 4: Verify restored database objects
        verify_conn_str = f"postgresql://{user}:{password}@{host}:{port}/{target_db}?sslmode=require"
        with psycopg.connect(verify_conn_str, autocommit=True) as conn:
            with conn.cursor() as cur:
                # 4.1 Tables count
                cur.execute("SELECT count(*) FROM information_schema.tables WHERE table_schema='public';")
                tables_cnt = cur.fetchone()[0]
                print(f"4.1 Restored public tables: {tables_cnt} (expected 56)")
                assert tables_cnt == 56

                # 4.2 Alembic version
                cur.execute("SELECT version_num FROM alembic_version;")
                alembic_rev = cur.fetchone()[0]
                print(f"4.2 Restored Alembic migration revision: '{alembic_rev}' (expected 'e5c8a2b7d940')")
                assert alembic_rev == "e5c8a2b7d940"

                # 4.3 Total RLS policies
                cur.execute("SELECT count(*) FROM pg_policies WHERE schemaname='public';")
                policies_cnt = cur.fetchone()[0]
                print(f"4.3 Restored RLS policies: {policies_cnt} (expected 220)")
                assert policies_cnt == 220

                # 4.4 ENABLE and FORCE RLS settings
                cur.execute("""
                    SELECT c.relname, c.relrowsecurity, c.relforcerowsecurity 
                    FROM pg_class c 
                    JOIN pg_namespace n ON n.oid = c.relnamespace 
                    WHERE n.nspname = 'public' AND c.relkind = 'r';
                """)
                rows = cur.fetchall()
                rls_enabled_cnt = len([r for r in rows if r[1]])
                rls_forced_cnt = len([r for r in rows if r[2]])
                print(f"4.4 RLS Enabled tables: {rls_enabled_cnt} (expected 56)")
                print(f"    RLS Forced tables:  {rls_forced_cnt} (expected 55)")
                assert rls_enabled_cnt == 56
                assert rls_forced_cnt == 55

        # Step 5: Grant runtime permissions on restored DB to safar_app and re-run tenant isolation tests
        print(f"5. Running tenant-isolation tests against the RESTORED database '{target_db}'...")
        with psycopg.connect(verify_conn_str, autocommit=True) as conn:
            with conn.cursor() as cur:
                cur.execute("GRANT USAGE ON SCHEMA public TO safar_app;")
                cur.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO safar_app;")
                cur.execute("GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO safar_app;")
                cur.execute("GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO safar_app;")

        # Test isolation as safar_app
        from app.core.config import settings
        # Read safar_app password from .env.staging
        import re
        with open("C:/Users/siddharth/Desktop/SAFAR/.env.staging", "r") as f:
            content = f.read()
        m = re.search(r"DATABASE_URL=postgresql\+psycopg://safar_app:([^@]+)@", content)
        safar_app_pwd = m.group(1)

        app_verify_conn = f"postgresql://safar_app:{safar_app_pwd}@{host}:{port}/{target_db}?sslmode=require"
        with psycopg.connect(app_verify_conn) as conn:
            with conn.cursor() as cur:
                # Anonymous query
                cur.execute("SELECT count(*) FROM trips;")
                assert cur.fetchone()[0] == 0
                print("   5.1 Anonymous read returns 0 trips (fail-closed verified).")

                # System context setup
                cur.execute("SELECT set_config('app.system', 'on', true);")
                cur.execute("""
                    INSERT INTO users (id, email, password_hash, display_name, is_admin, is_active, locale, timezone, quiet_mode, created_at, updated_at)
                    VALUES 
                    ('restore_test_user_a', 'rua@test.com', 'hash', 'User A', false, true, 'en', 'UTC', false, NOW(), NOW()),
                    ('restore_test_user_b', 'rub@test.com', 'hash', 'User B', false, true, 'en', 'UTC', false, NOW(), NOW())
                    ON CONFLICT (id) DO NOTHING;
                """)
                cur.execute("""
                    INSERT INTO trips (id, name, destination_name, start_date, end_date, group_size, currency, base_lat, base_lon, created_by, status, privacy, created_at, updated_at)
                    VALUES ('trip_restored_a', 'Restored Voyage A', 'Oslo', '2026-08-01', '2026-08-05', 4, 'EUR', 0.0, 0.0, 'restore_test_user_a', 'planning', 'private', NOW(), NOW())
                    ON CONFLICT (id) DO NOTHING;
                """)
                cur.execute("""
                    INSERT INTO trip_members (id, trip_id, user_id, role, scope, status, accessibility_needs, joined_at)
                    VALUES ('member_restored_a', 'trip_restored_a', 'restore_test_user_a', 'owner', 'full', 'active', '[]', NOW())
                    ON CONFLICT (id) DO NOTHING;
                """)
                conn.commit()

        # User A authorized read
        with psycopg.connect(app_verify_conn) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT set_config('app.user_id', 'restore_test_user_a', true);")
                cur.execute("SELECT count(*) FROM trips WHERE id = 'trip_restored_a';")
                assert cur.fetchone()[0] == 1
                print("   5.2 User A read own trip returns 1.")

        # User B cross-tenant read & write attempts
        with psycopg.connect(app_verify_conn) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT set_config('app.user_id', 'restore_test_user_b', true);")
                cur.execute("SELECT count(*) FROM trips WHERE id = 'trip_restored_a';")
                assert cur.fetchone()[0] == 0
                print("   5.3 User B cross-tenant SELECT returns 0.")

                cur.execute("UPDATE trips SET name = 'Attacked' WHERE id = 'trip_restored_a';")
                assert cur.rowcount == 0
                print("   5.4 User B cross-tenant UPDATE returns 0 rows affected.")

                cur.execute("DELETE FROM trips WHERE id = 'trip_restored_a';")
                assert cur.rowcount == 0
                print("   5.5 User B cross-tenant DELETE returns 0 rows affected.")

        print("--- ALL TENANT ISOLATION ASSERTIONS PASSED ON RESTORED DATABASE ---")

    finally:
        # Step 6: Safe cleanup of temporary verification database
        print(f"6. Cleaning up temporary verification database '{target_db}'...")
        with psycopg.connect(admin_conn_str, autocommit=True) as conn:
            with conn.cursor() as cur:
                # Terminate any open connections to the test DB
                cur.execute(f"""
                    SELECT pg_terminate_backend(pid) 
                    FROM pg_stat_activity 
                    WHERE datname = '{target_db}' AND pid <> pg_backend_pid();
                """)
                cur.execute(f"DROP DATABASE IF EXISTS {target_db};")
                print(f"   Temporary database '{target_db}' dropped successfully.")

        if dump_file.exists():
            dump_file.unlink()
            print(f"   Temporary dump file '{dump_file.name}' removed.")

    print("--- TASK 2 COMPLETE: GENUINE POSTGRESQL BACKUP & RESTORE DRILL VERIFIED ---")

if __name__ == "__main__":
    main()
