"""PostgreSQL Backup & Recovery Observability for SAFAR Staging.

Provides automated custom-format logical backups using pg_dump -Fc,
manifest tracking with SHA256 integrity verification, retention management,
and non-destructive restore verification against a temporary test database.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import logging
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from typing import Any

logging.basicConfig(
    level=logging.INFO,
    format='{"ts":"%(asctime)s","level":"%(levelname)s","logger":"%(name)s","message":"%(message)s"}',
)
logger = logging.getLogger("safar.backup")

TOOLS_BIN = Path("C:/Users/siddharth/Desktop/SAFAR/tools/pgsql/bin")
DEFAULT_BACKUP_DIR = Path("C:/Users/siddharth/Desktop/SAFAR/storage_staging/backups")
MANIFEST_FILE = DEFAULT_BACKUP_DIR / "backup_manifest.json"


def get_db_credentials() -> dict[str, str]:
    """Reads connection parameters from .env.staging or environment."""
    staging_env = Path("C:/Users/siddharth/Desktop/SAFAR/.env.staging")
    content = ""
    if staging_env.exists():
        content = staging_env.read_text(encoding="utf-8")

    # Use pooler for reliable IPv4 transport on port 5432
    host = "aws-0-ap-south-1.pooler.supabase.com"
    port = "5432"
    user = "postgres.qekbbbkmhpvdktctfgow"
    password = "safarisatravellingapp"
    source_db = "postgres"
    safar_app_pwd = "safar_app_sec_d09eb115a3ef5fcdc84dcdebec069668"

    m = re.search(r"DATABASE_URL=postgresql\+psycopg://safar_app(?:\.qekbbbkmhpvdktctfgow)?:([^@]+)@", content)
    if m:
        safar_app_pwd = m.group(1)

    return {
        "host": host,
        "port": port,
        "user": user,
        "password": password,
        "source_db": source_db,
        "safar_app_pwd": safar_app_pwd,
    }


def record_manifest(backup_record: dict[str, Any]) -> None:
    DEFAULT_BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    manifest: dict[str, Any] = {"version": "1.0", "backups": []}
    if MANIFEST_FILE.exists():
        try:
            manifest = json.loads(MANIFEST_FILE.read_text(encoding="utf-8"))
        except Exception:
            pass

    manifest["backups"].append(backup_record)
    MANIFEST_FILE.write_text(json.dumps(manifest, indent=2), encoding="utf-8")


def enforce_retention(max_backups: int = 7) -> None:
    """Retains the most recent N successful backups, cleaning up older local dumps.
    
    Guarantees:
    - The most recent successful backup is NEVER pruned.
    - Failed backups NEVER replace, displace, or cause pruning of valid backups.
    """
    if not MANIFEST_FILE.exists():
        return
    try:
        manifest = json.loads(MANIFEST_FILE.read_text(encoding="utf-8"))
        all_backups = manifest.get("backups", [])
        
        # Partition into successful and failed
        successful = [b for b in all_backups if b.get("status") == "success"]
        failed = [b for b in all_backups if b.get("status") == "failed"]
        
        retained_successful = successful
        if len(successful) > max_backups:
            # Slicing :-max_backups prunes only the oldest, strictly preserving the newest
            to_prune = successful[:-max_backups]
            retained_successful = successful[-max_backups:]
            for b in to_prune:
                file_path = Path(b.get("path", ""))
                if file_path.exists() and file_path != MANIFEST_FILE:
                    try:
                        file_path.unlink()
                        logger.info(f"Retention policy: pruned old backup {file_path.name}")
                    except Exception as e:
                        logger.warning(f"Could not remove old backup {file_path}: {e}")
                        
        # Keep up to 10 recent failure records for auditing, but they do NOT count towards the 7 successful dumps
        retained_failed = failed[-10:] if len(failed) > 10 else failed
        
        combined = retained_successful + retained_failed
        combined.sort(key=lambda x: x.get("timestamp", ""))
        manifest["backups"] = combined
        MANIFEST_FILE.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    except Exception as exc:
        logger.warning(f"Retention enforcement error: {exc}")


def verify_manifest_integrity(manifest_path: Path | None = None) -> dict[str, Any]:
    """Verifies manifest consistency and cryptographic SHA-256 hashes against disk."""
    m_path = manifest_path or MANIFEST_FILE
    if not m_path.exists():
        return {"valid": False, "error": "Manifest file not found"}

    try:
        manifest = json.loads(m_path.read_text(encoding="utf-8"))
        backups = manifest.get("backups", [])
        verified_count = 0
        failed_records = 0
        errors = []

        for b in backups:
            status = b.get("status")
            fpath = Path(b.get("path", ""))
            if status == "success":
                if not fpath.exists():
                    errors.append(f"Missing backup file: {fpath}")
                    continue
                actual_size = os.path.getsize(fpath)
                if actual_size != b.get("size_bytes"):
                    errors.append(f"Size mismatch on {fpath.name}: expected {b.get('size_bytes')}, got {actual_size}")
                    continue
                with open(fpath, "rb") as f:
                    actual_sha = hashlib.sha256(f.read()).hexdigest()
                if actual_sha.lower() != b.get("sha256", "").lower():
                    errors.append(f"Hash mismatch on {fpath.name}: expected {b.get('sha256')}, got {actual_sha}")
                    continue
                verified_count += 1
            elif status == "failed":
                failed_records += 1
                if fpath.exists() and fpath.is_file():
                    errors.append(f"Ghost dump file exists for failed backup: {fpath}")

        return {
            "valid": len(errors) == 0,
            "total_records": len(backups),
            "successful_verified": verified_count,
            "failed_records": failed_records,
            "errors": errors,
        }
    except Exception as exc:
        return {"valid": False, "error": str(exc)}


def create_backup(backup_dir: Path | None = None) -> dict[str, Any]:
    out_dir = backup_dir or DEFAULT_BACKUP_DIR
    out_dir.mkdir(parents=True, exist_ok=True)

    pg_dump_exe = TOOLS_BIN / "pg_dump.exe"
    if not pg_dump_exe.exists():
        pg_dump_exe = Path("pg_dump")

    creds = get_db_credentials()
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    filename = f"safar_staging_backup_{timestamp}.dump"
    dump_path = out_dir / filename

    env = dict(os.environ)
    env["PGPASSWORD"] = creds["password"]
    env["PATH"] = f"{TOOLS_BIN};" + env.get("PATH", "")

    cmd = [
        str(pg_dump_exe),
        "-h", creds["host"],
        "-p", creds["port"],
        "-U", creds["user"],
        "-d", creds["source_db"],
        "-Fc",
        "-f", str(dump_path),
    ]

    t0 = time.time()
    logger.info(f"Starting pg_dump -Fc to {dump_path.name}...")
    res = subprocess.run(cmd, env=env, capture_output=True, text=True)
    duration = round(time.time() - t0, 2)

    if res.returncode != 0:
        logger.error(f"pg_dump failed (code {res.returncode}): {res.stderr}")
        # Clean up partial/corrupted dump file if created
        if dump_path.exists():
            try:
                dump_path.unlink()
            except Exception:
                pass
        record = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "filename": filename,
            "path": str(dump_path),
            "status": "failed",
            "duration_seconds": duration,
            "error": res.stderr[:300],
        }
        record_manifest(record)
        raise RuntimeError(f"pg_dump failed: {res.stderr}")

    size_bytes = os.path.getsize(dump_path)
    with open(dump_path, "rb") as f:
        sha256 = hashlib.sha256(f.read()).hexdigest()

    logger.info(f"Backup completed successfully in {duration}s! Size: {size_bytes} bytes, SHA256: {sha256[:16]}...")
    record = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "filename": filename,
        "path": str(dump_path),
        "status": "success",
        "size_bytes": size_bytes,
        "sha256": sha256,
        "duration_seconds": duration,
        "verified": False,
    }
    record_manifest(record)
    enforce_retention(max_backups=7)
    return record


def verify_restore(dump_path: Path) -> dict[str, Any]:
    """Non-destructive restore drill into temporary safar_restore_verify database."""
    import psycopg

    pg_restore_exe = TOOLS_BIN / "pg_restore.exe"
    if not pg_restore_exe.exists():
        pg_restore_exe = Path("pg_restore")

    creds = get_db_credentials()
    target_db = "safar_restore_verify"

    env = dict(os.environ)
    env["PGPASSWORD"] = creds["password"]
    env["PATH"] = f"{TOOLS_BIN};" + env.get("PATH", "")

    admin_conn_str = f"postgresql://{creds['user']}:{creds['password']}@{creds['host']}:{creds['port']}/{creds['source_db']}?sslmode=require"

    logger.info(f"Provisioning temporary verification database '{target_db}'...")
    with psycopg.connect(admin_conn_str, autocommit=True) as conn:
        with conn.cursor() as cur:
            cur.execute(f"DROP DATABASE IF EXISTS {target_db};")
            cur.execute(f"CREATE DATABASE {target_db};")

    try:
        t0 = time.time()
        logger.info(f"Running pg_restore into '{target_db}'...")
        restore_cmd = [
            str(pg_restore_exe),
            "-h", creds["host"],
            "-p", creds["port"],
            "-U", creds["user"],
            "-d", target_db,
            "--no-owner",
            "--no-privileges",
            str(dump_path),
        ]
        res = subprocess.run(restore_cmd, env=env, capture_output=True, text=True)
        restore_duration = round(time.time() - t0, 2)
        logger.info(f"pg_restore completed in {restore_duration}s (exit code {res.returncode}).")

        # Verify database objects
        verify_conn_str = f"postgresql://{creds['user']}:{creds['password']}@{creds['host']}:{creds['port']}/{target_db}?sslmode=require"
        with psycopg.connect(verify_conn_str, autocommit=True) as conn:
            with conn.cursor() as cur:
                # Tables count
                cur.execute("SELECT count(*) FROM information_schema.tables WHERE table_schema='public';")
                tables_cnt = cur.fetchone()[0]

                # Alembic revision
                cur.execute("SELECT version_num FROM alembic_version;")
                alembic_rev = cur.fetchone()[0]

                # Total RLS policies
                cur.execute("SELECT count(*) FROM pg_policies WHERE schemaname='public';")
                policies_cnt = cur.fetchone()[0]

                # ENABLE and FORCE RLS settings
                cur.execute("""
                    SELECT c.relname, c.relrowsecurity, c.relforcerowsecurity 
                    FROM pg_class c 
                    JOIN pg_namespace n ON n.oid = c.relnamespace 
                    WHERE n.nspname = 'public' AND c.relkind = 'r';
                """)
                rows = cur.fetchall()
                rls_enabled_cnt = len([r for r in rows if r[1]])
                rls_forced_cnt = len([r for r in rows if r[2]])

                # Grant runtime access to safar_app to verify tenant isolation
                cur.execute("GRANT USAGE ON SCHEMA public TO safar_app;")
                cur.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO safar_app;")
                cur.execute("GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO safar_app;")
                cur.execute("GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO safar_app;")

        # Test isolation as safar_app
        app_user = "safar_app.qekbbbkmhpvdktctfgow" if "pooler" in creds["host"] else "safar_app"
        app_verify_conn = f"postgresql://{app_user}:{creds['safar_app_pwd']}@{creds['host']}:{creds['port']}/{target_db}?sslmode=require"
        with psycopg.connect(app_verify_conn) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT count(*) FROM trips;")
                anon_trips = cur.fetchone()[0]

        logger.info(f"Verification Results: tables={tables_cnt}, revision={alembic_rev}, policies={policies_cnt}, rls_enabled={rls_enabled_cnt}, rls_forced={rls_forced_cnt}, anon_trips={anon_trips}")

        assert tables_cnt == 56, f"Expected 56 tables, got {tables_cnt}"
        assert alembic_rev == "e5c8a2b7d940", f"Expected revision e5c8a2b7d940, got {alembic_rev}"
        assert policies_cnt == 220, f"Expected 220 RLS policies, got {policies_cnt}"
        assert rls_enabled_cnt == 56, f"Expected 56 RLS enabled tables, got {rls_enabled_cnt}"
        assert rls_forced_cnt == 55, f"Expected 55 RLS forced tables, got {rls_forced_cnt}"
        assert anon_trips == 0, f"Expected fail-closed 0 trips for anonymous context, got {anon_trips}"

        # Mark verified in manifest
        if MANIFEST_FILE.exists():
            manifest = json.loads(MANIFEST_FILE.read_text(encoding="utf-8"))
            for b in manifest.get("backups", []):
                if b.get("path") == str(dump_path):
                    b["verified"] = True
                    b["verified_at"] = datetime.now(timezone.utc).isoformat()
                    b["verified_tables"] = tables_cnt
                    b["verified_revision"] = alembic_rev
            MANIFEST_FILE.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

        return {
            "status": "passed",
            "tables": tables_cnt,
            "revision": alembic_rev,
            "policies": policies_cnt,
            "rls_enabled": rls_enabled_cnt,
            "rls_forced": rls_forced_cnt,
            "isolation_verified": True,
        }

    finally:
        logger.info(f"Tearing down temporary database '{target_db}'...")
        with psycopg.connect(admin_conn_str, autocommit=True) as conn:
            with conn.cursor() as cur:
                cur.execute(f"DROP DATABASE IF EXISTS {target_db};")
        logger.info("Temporary database dropped cleanly.")


def main():
    parser = argparse.ArgumentParser(description="SAFAR Staging Backup & Recovery Tool")
    parser.add_argument("--verify", action="store_true", help="Run restore verification drill after backup")
    args = parser.parse_args()

    record = create_backup()
    dump_path = Path(record["path"])

    if args.verify:
        verify_restore(dump_path)
        logger.info("--- ALL BACKUP & RESTORE VERIFICATIONS PASSED ---")


if __name__ == "__main__":
    main()
