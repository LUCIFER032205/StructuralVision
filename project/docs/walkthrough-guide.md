# Structural Vision AR — Walkthrough Guide

How to start the backend, run the app, and check logs. Written 2026-07-21.

---

## 1. Start the backend

Open **Git Bash** and run:

```bash
cd /f/Major_project/Major_project/backend
set -a && . ./.env && set +a
/c/Python314/python -m uvicorn main:app --host 0.0.0.0
```

Line by line:
- `set -a && . ./.env && set +a` — loads Supabase keys from `.env` into the environment.
- `--host 0.0.0.0` — makes the server reachable from the phone over Wi-Fi (without it, only the PC itself can connect).
- `/c/Python314/python` — full path because uvicorn is not on PATH (no venv on this machine).

**You know it worked when you see:**

```
INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
INFO:     Application startup complete.
```

Leave this window open — this window IS your backend log (see section 4).

### Quick health check

In a second terminal (or browser):

```bash
curl http://localhost:8000/docs
```

Browser: `http://localhost:8000/docs` shows the FastAPI Swagger page → backend is alive.

---

## 2. Connect the phone

The app needs to reach the backend. Two options:

### Option A — Same Wi-Fi (normal use)

1. Phone and PC on the **same Wi-Fi network**.
2. Find the PC's LAN IP: run `ipconfig` in cmd, look for "Wireless LAN adapter Wi-Fi" → IPv4 Address. Last known: `192.168.0.183` (changes when the router reassigns; ignore `192.168.56.1`, that's VirtualBox).
3. The APK's default is already the LAN IP. If the IP changed, use the **gear icon on the login screen** → enter `http://<new-ip>:8000` → saved permanently, no rebuild needed.
4. Windows Firewall rule "StructVisionAPI" (TCP 8000) already exists — if a fresh machine, allow port 8000 inbound.

### Option B — ngrok tunnel (remote demo / different network)

```bash
F:/StructuralVision/ngrok.exe http 8000
```

The URL is **always** `https://purr-decline-paycheck.ngrok-free.dev` (static free ngrok domain). Paste it into the **gear icon dialog** on the app's login screen once — it never changes.

The APK itself is also downloadable through the tunnel: `https://purr-decline-paycheck.ngrok-free.dev/static/structural_vision_ar.apk`

---

## 3. Use the app

1. **Install**: `app\build\app\outputs\flutter-apk\app-release.apk` — copy to phone and install, or `adb install -r` with USB debugging.
2. **Login**: Supabase email/password. Test account: `structvision.apptest@gmail.com` / `AppTest123!`
   - Wrong server URL → "connection" errors here. Fix via gear icon.
3. **Scan**: camera screen → shoot a structural element (or gallery button left of the shutter to pick a photo, e.g. from `demo_kit\`). App uploads, polls every 2 s, ~1–3 s inference.
4. **Result screen**: photo with crack polygons drawn, component type, risk badge (LOW/MEDIUM/HIGH), share-PDF button.
5. **AR screen** (button on result screen):
   - Move the phone slowly over the floor/surface until a dotted plane appears (~1 min in release build).
   - **Tap the plane** → crack overlay quad appears (1 m, anchored), each crack colored by severity with a numbered label. No cracks → risk-colored pin instead.
   - **AppBar toggle icon**: switch horizontal ↔ vertical plane detection (wall mode). ⚠️ Vertical is untested on the Vivo — if the app crashes, that's the known ARCore issue; just relaunch and stay horizontal.
   - **Measure FAB**: tap it, then tap two points on the plane (e.g. both ends of a real crack) → distance in cm shown in the badge.
6. **History** (icon on camera screen): past scans, tap one to reopen its full result.

---

## 4. Checking logs

### Backend log (most useful)

It's simply the uvicorn terminal window. Every request prints one line:

```
INFO:  192.168.0.101:54321 - "POST /scan HTTP/1.1" 200 OK          ← upload accepted
INFO:  192.168.0.101:54322 - "GET /scan/<id> HTTP/1.1" 200 OK      ← app polling
INFO:  192.168.0.101:54323 - "GET /scan/<id>/overlay.glb" 200 OK   ← AR overlay fetched
```

How to read it:
- **No lines at all when using the app** → phone can't reach the PC. Check Wi-Fi / IP / gear-icon URL.
- **401** → auth problem (bad login / expired session — log out and back in).
- **404 on overlay.glb** → scan still pending or wrong scan id (normally transient).
- **500 + Python traceback printed below it** → backend bug; the traceback names file and line.

To keep a log file as well:

```bash
/c/Python314/python -m uvicorn main:app --host 0.0.0.0 2>&1 | tee backend.log
```

### Phone-side log (when the app misbehaves and the backend log is silent)

USB-connect the phone (USB debugging is enabled on the Vivo), then:

```bash
/f/android-sdk/platform-tools/adb logcat -s flutter
```

Shows Dart-side prints/exceptions. For AR/ARCore native crashes drop the filter and search:

```bash
/f/android-sdk/platform-tools/adb logcat | grep -iE "arcore|libarcore|SIGSEGV|flutter"
```

### Data in Supabase

Dashboard → Table Editor → `scans` (one row per scan: status, risk, component) and
`crack_detections` (per-crack bbox/polygon/confidence). Storage → `scan-images` bucket holds uploaded photos.

---

## 5. Common problems

| Symptom | Cause → Fix |
|---|---|
| "Invalid API key" at login | Old APK with placeholder key → reinstall current APK |
| Login network error | Phone offline, or gear-icon URL wrong |
| Scan stuck "pending" > 2 min | Backend crashed mid-inference → check terminal for traceback |
| AR "Marker failed to load" | Backend unreachable from phone, or scan has no overlay yet → check backend log for `overlay.glb` line |
| AR planes never appear | Poor lighting / textureless floor; move phone slowly; release build needs ~1 min |
| App crash entering AR after camera | Should be fixed (camera disposed before AR); if it recurs, grab `adb logcat` |
| Everything worked yesterday, dead today | Router gave PC a new IP → `ipconfig`, update gear-icon URL |

---

## 6. One-glance startup checklist

```
[ ] Git Bash: cd backend, load .env, start uvicorn --host 0.0.0.0
[ ] See "Application startup complete"
[ ] http://localhost:8000/docs opens in browser
[ ] Phone on same Wi-Fi (or tunnel running + URL pasted in gear icon)
[ ] Login on phone works
[ ] Test scan with a demo_kit photo → result in ~3 s
```
