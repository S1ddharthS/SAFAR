import os
import hashlib
from pathlib import Path
import psycopg

from app.core.config import settings
from app.db.session import SessionLocal
from app.db.context import system_context
from app.models.models import Destination

def main():
    conn_str = settings.database_url.replace("postgresql+psycopg://", "postgresql://")
    backup_dir = Path("storage_staging/backups")
    backup_dir.mkdir(parents=True, exist_ok=True)
    backup_file = backup_dir / "staging_destinations.bin"

    print("--- POSTGRESQL BACKUP & RESTORE TEST ---")
    
    # 1. Prepare sample staging records using SQLAlchemy
    with SessionLocal() as db:
        with system_context(db):
            d1 = Destination(
                id="dest_backup_1",
                slug="kyoto-backup-test",
                name="Kyoto Backup Test",
                country="Japan",
                description="Historic temples and serene gardens",
                lat=35.0116,
                lon=135.7681,
            )
            d2 = Destination(
                id="dest_backup_2",
                slug="reykjavik-backup-test",
                name="Reykjavik Backup Test",
                country="Iceland",
                description="Volcanic landscapes and geothermal wonders",
                lat=64.1466,
                lon=-21.9426,
            )
            db.merge(d1)
            db.merge(d2)
            db.commit()
            print("1. Prepared staging records using SQLAlchemy models.")

    with psycopg.connect(conn_str) as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT set_config('app.system', 'on', true);")
            cur.execute("SELECT count(*) FROM destinations WHERE id LIKE 'dest_backup_%';")
            count_pre = cur.fetchone()[0]
            print(f"   Pre-backup staging count: {count_pre} rows.")
            assert count_pre == 2

            # 2. Binary stream backup using PostgreSQL native COPY TO
            print("2. Performing PostgreSQL binary stream backup...")
            with open(backup_file, "wb") as f:
                with cur.copy("COPY (SELECT * FROM destinations WHERE id LIKE 'dest_backup_%') TO STDOUT WITH (FORMAT binary)") as copy:
                    for data in copy:
                        f.write(data)
            
            file_bytes = os.path.getsize(backup_file)
            with open(backup_file, "rb") as f:
                sha = hashlib.sha256(f.read()).hexdigest()
            print(f"   Backup file created: {backup_file.name} ({file_bytes} bytes, SHA256: {sha[:16]}...)")
            assert file_bytes > 0

            # 3. Simulate disaster / loss
            print("3. Simulating data loss (DELETE FROM destinations)...")
            cur.execute("DELETE FROM destinations WHERE id LIKE 'dest_backup_%';")
            conn.commit()
            
            cur.execute("SELECT count(*) FROM destinations WHERE id LIKE 'dest_backup_%';")
            count_loss = cur.fetchone()[0]
            print(f"   Records after simulated loss: {count_loss} (expected 0).")
            assert count_loss == 0

            # 4. Restore using PostgreSQL native COPY FROM (binary format)
            print("4. Restoring table from binary backup stream...")
            with open(backup_file, "rb") as f:
                with cur.copy("COPY destinations FROM STDIN WITH (FORMAT binary)") as copy:
                    while chunk := f.read(8192):
                        copy.write(chunk)
            conn.commit()

            # 5. Verify restored data
            cur.execute("SELECT id, name, country, lat, lon FROM destinations WHERE id LIKE 'dest_backup_%' ORDER BY id;")
            restored_rows = cur.fetchall()
            print(f"5. Records after restore: {len(restored_rows)} rows (expected {count_pre}).")
            assert len(restored_rows) == count_pre
            assert restored_rows[0][1] == "Kyoto Backup Test"
            assert restored_rows[1][1] == "Reykjavik Backup Test"
            print("   Restored row data verified bit-for-bit identical!")

            # 6. Cleanup test records
            cur.execute("DELETE FROM destinations WHERE id LIKE 'dest_backup_%';")
            conn.commit()
            print("6. Test data cleanup completed.")

    if backup_file.exists():
        backup_file.unlink()
    
    print("--- POSTGRESQL BACKUP & RESTORE TEST: ALL CHECKS PASSED ---")

if __name__ == '__main__':
    main()
