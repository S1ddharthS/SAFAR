import os
import secrets
from pathlib import Path
import psycopg
from app.core.config import settings

def main():
    admin_url = settings.database_url.replace("postgresql+psycopg://", "postgresql://")
    app_pwd = "safar_app_sec_" + secrets.token_hex(16)

    # 1. Configure safar_app role using admin credentials
    with psycopg.connect(admin_url) as conn:
        conn.autocommit = True
        with conn.cursor() as cur:
            cur.execute(f"ALTER ROLE safar_app WITH PASSWORD '{app_pwd}';")
            cur.execute("GRANT CONNECT ON DATABASE postgres TO safar_app;")
            cur.execute("GRANT USAGE ON SCHEMA public TO safar_app;")
            cur.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO safar_app;")
            cur.execute("GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO safar_app;")
            cur.execute("GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO safar_app;")
            cur.execute("ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO safar_app;")
            cur.execute("ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO safar_app;")
            print("1. safar_app configured with full runtime permissions.")

    # 2. Update .env.staging to use safar_app
    env_staging = Path("../../.env.staging").resolve()
    with open(env_staging, "r", encoding="utf-8") as f:
        lines = f.readlines()

    new_lines = []
    for line in lines:
        if line.startswith("DATABASE_URL="):
            host_part = line.split("@")[1]
            new_lines.append(f"DATABASE_URL=postgresql+psycopg://safar_app:{app_pwd}@{host_part}")
        else:
            new_lines.append(line)

    with open(env_staging, "w", encoding="utf-8") as f:
        f.writelines(new_lines)

    print("2. Updated .env.staging with restricted safar_app role.")

if __name__ == "__main__":
    main()
