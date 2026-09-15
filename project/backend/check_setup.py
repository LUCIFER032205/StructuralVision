"""
check_setup.py — run before starting the backend. Tells you exactly what's broken.

    C:\\Python314\\python.exe check_setup.py
"""
import importlib
import json
import os
import socket
import sys
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
fails = 0


def ok(msg):
    print(f"  [OK]   {msg}")


def bad(msg, fix):
    global fails
    fails += 1
    print(f"  [FAIL] {msg}\n         FIX: {fix}")


print("\n1. Python + packages")
ok(f"Python {sys.version.split()[0]} at {sys.executable}")
for mod in ["fastapi", "uvicorn", "multipart", "ultralytics", "PIL", "numpy", "supabase", "jose"]:
    try:
        importlib.import_module(mod)
        ok(mod)
    except Exception as e:
        bad(f"{mod} not importable ({e})", f'"{sys.executable}" -m pip install -r requirements.txt')

print("\n2. backend/.env")
env = HERE / ".env"
if not env.exists():
    bad(".env missing", "copy .env.example to .env and fill in the Supabase values")
else:
    for line in env.read_text(encoding="utf-8").splitlines():
        k, sep, v = line.strip().partition("=")
        if sep and not k.startswith("#"):
            os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))
url = os.environ.get("SUPABASE_URL", "").rstrip("/")
key = os.environ.get("SUPABASE_SERVICE_KEY", "")
for name, val in [("SUPABASE_URL", url), ("SUPABASE_SERVICE_KEY", key)]:
    if not val or "your-" in val:
        bad(f"{name} empty/placeholder", "Supabase dashboard -> Project Settings -> API Keys, paste into backend/.env")
    else:
        ok(f"{name} set")

print("\n3. Supabase")
if url and key:
    def get(path, auth=True):
        headers = {"apikey": key, "Authorization": f"Bearer {key}"} if auth else {}
        req = urllib.request.Request(url + path, headers=headers)
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status, r.read()

    try:
        socket.gethostbyname(url.split("//")[-1])
        ok("DNS resolves")
        try:
            get("/auth/v1/.well-known/jwks.json", auth=False)
            ok("Auth JWKS reachable (phone logins can be verified)")
        except Exception as e:
            bad(f"JWKS fetch failed: {e}", "project paused? see step 3 of RUN_GUIDE.md")
        for table in ["scans", "crack_detections"]:
            try:
                get(f"/rest/v1/{table}?select=id&limit=1")
                ok(f"table '{table}' readable")
            except urllib.error.HTTPError as e:
                body = e.read().decode(errors="ignore")[:200]
                if e.code == 401:
                    bad(f"'{table}': 401 {body}", "SUPABASE_SERVICE_KEY is wrong — use the secret/service_role key, not anon")
                elif e.code == 404:
                    bad(f"'{table}': table missing", "run backend/schema.sql in Supabase SQL Editor")
                else:
                    bad(f"'{table}': HTTP {e.code} {body}", "project paused/restoring? open the Supabase dashboard")
        try:
            _, raw = get("/storage/v1/bucket")
            names = [b["name"] for b in json.loads(raw)]
            if "scan-images" in names:
                ok("storage bucket 'scan-images' exists")
            else:
                print("  [info] bucket 'scan-images' not there yet — backend creates it on startup")
        except Exception as e:
            bad(f"storage check failed: {e}", "check service key / project status")
    except socket.gaierror:
        bad(f"cannot resolve {url}", "no internet, wrong SUPABASE_URL, or project deleted")
    except urllib.error.URLError as e:
        bad(f"cannot reach Supabase: {e.reason}", "check internet / VPN (Cloudflare WARP) / project paused")

print("\n4. Model files")
models = HERE.parent / "models"
for f in ["crack_seg.pt", "component.onnx"]:
    p = models / f
    if p.exists():
        ok(f"{f} ({p.stat().st_size // 1_000_000} MB)")
    elif f == "crack_seg.pt":
        bad(f"{p} missing", "copy the trained weights into project/models/")
    else:
        print(f"  [info] {f} not found (optional)")

print("\n5. Port 8000 + network")
with socket.socket() as s:
    if s.connect_ex(("127.0.0.1", 8000)) == 0:
        print("  [info] something is ALREADY on port 8000 (backend already running? stop it first to restart)")
    else:
        ok("port 8000 free")
ips = [ip for ip in socket.gethostbyname_ex(socket.gethostname())[2]
       if not ip.startswith(("127.", "169.254."))]
for ip in ips:
    if ip.startswith("192.168.56."):
        print(f"  [skip] {ip}  (VirtualBox — not this one)")
    elif ip.startswith("172.16.0."):
        print(f"  [skip] {ip}  (Cloudflare WARP — not this one)")
    else:
        ok(f"LAN IP candidate: {ip}  ->  phone URL: http://{ip}:8000")
print("  [info] unsure? PowerShell: Get-NetIPAddress -InterfaceAlias Wi-Fi -AddressFamily IPv4")

print("\n" + ("ALL GOOD — start the backend." if not fails else f"{fails} problem(s) above. Fix them first."))
sys.exit(1 if fails else 0)
