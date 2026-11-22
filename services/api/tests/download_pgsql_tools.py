import os
import sys
import time
import zipfile
import urllib.request
from pathlib import Path

def main():
    # SAFAR_PG_BIN overrides the repository-local tools directory.
    tools_bin = Path(os.environ.get("SAFAR_PG_BIN", str(Path(__file__).resolve().parents[3] / "tools" / "pgsql" / "bin")))
    tools_dir = tools_bin.parent
    tools_dir.mkdir(parents=True, exist_ok=True)
    zip_path = tools_dir / "pgsql_binaries.zip"

    url = "https://get.enterprisedb.com/postgresql/postgresql-17.2-1-windows-x64-binaries.zip"
    headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}

    print(f"Downloading PostgreSQL binaries from {url}...")
    req = urllib.request.Request(url, headers=headers)
    
    t0 = time.time()
    with urllib.request.urlopen(req) as resp, open(zip_path, "wb") as out_file:
        total_size = int(resp.headers.get("Content-Length", 0))
        downloaded = 0
        chunk_size = 1024 * 1024  # 1MB chunks
        
        while chunk := resp.read(chunk_size):
            out_file.write(chunk)
            downloaded += len(chunk)
            elapsed = time.time() - t0
            speed = (downloaded / (1024 * 1024)) / (elapsed + 0.001)
            percent = (downloaded / total_size) * 100 if total_size else 0
            sys.stdout.write(f"\rDownloaded {downloaded // (1024*1024)}MB / {total_size // (1024*1024)}MB ({percent:.1f}%) at {speed:.2f} MB/s")
            sys.stdout.flush()

    print("\nDownload complete. Extracting pg_dump, pg_restore and dependencies...")
    with zipfile.ZipFile(zip_path, "r") as z:
        for member in z.namelist():
            # Extract pgsql/bin and pgsql/lib
            if member.startswith("pgsql/bin/") or member.startswith("pgsql/lib/"):
                z.extract(member, tools_dir.parent)
    
    print("Extraction complete. Cleaning up zip file...")
    if zip_path.exists():
        zip_path.unlink()
    
    pg_dump = tools_dir / "bin" / "pg_dump.exe"
    pg_restore = tools_dir / "bin" / "pg_restore.exe"
    print(f"pg_dump path: {pg_dump.exists()} ({pg_dump})")
    print(f"pg_restore path: {pg_restore.exists()} ({pg_restore})")

if __name__ == "__main__":
    main()
