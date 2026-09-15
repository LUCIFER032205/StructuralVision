# StructuralVision AR: Run Guide (VS Code)

How to start the backend, connect the phone, and rebuild the APK, all from VS Code.
Every command is also available as a VS Code **Task**, so you rarely need to type anything.

---

## 0. One-time setup (already done on this PC)

| Thing | Where it lives | Status |
|---|---|---|
| Python 3.14 + packages | `C:\Python314\python.exe` | installed (`pip install -r project/backend/requirements.txt`) |
| Backend secrets | `project/backend/.env` | filled in (gitignored) |
| App build keys | `project/app/dart_defines.env` | filled in (gitignored) |
| ML weights | `project/models/crack_seg.pt`, `component.onnx` | present |
| Flutter SDK | `F:\flutter` | 3.32.5 |
| Android SDK / adb | `F:\android-sdk` | present |
| JDK for APK builds | `F:\StructuralVision\tools\jdk-17` | present (the `java` on PATH is Java 8, **too old**. The build task sets JAVA_HOME for you.) |
| ngrok | `F:\StructuralVision\tools\ngrok.exe` | present |
| Firewall rule `StructVisionAPI` (TCP 8000 inbound) | Windows Firewall | enabled |
| VS Code Python extension | `ms-python.python` + `debugpy` | installed |

> **New PC?** Recreate the rows above. `.env` format is in `project/backend/.env.example`.
> `dart_defines.env` needs `SUPABASE_URL`, `SUPABASE_ANON_KEY` (the `sb_publishable_...` key) and `DEFAULT_API_BASE`.

---

## 1. Open the project in VS Code

**File → Open Folder… → `F:\StructuralVision`** (the repo root, not `project/`).
The `.vscode/` folder with the tasks and launch config lives there.

To run a task: **`Ctrl+Shift+P` → "Tasks: Run Task"** → pick one:

| Task | What it does |
|---|---|
| `1. Check setup (Supabase, keys, models, IP)` | Preflight. **Always run first.** |
| `2. Start backend` | Starts FastAPI on port 8000 |
| `3. ngrok tunnel (phone on other network)` | Public HTTPS URL for the phone |
| `APK: build release (+ copy to backend/static)` | Builds the APK |
| `APK: install on USB phone` | `adb install -r` the built APK |
| `Phone: logcat (flutter)` | Live app logs from a USB phone |

---

## 2. Start the backend

### Step 1: Preflight check
Run task **`1. Check setup`**. It checks, in order:

1. Python packages import
2. `backend/.env` has real `SUPABASE_URL` + `SUPABASE_SERVICE_KEY`
3. **Supabase**: DNS, auth keys (JWKS), `scans` + `crack_detections` tables, `scan-images` bucket
4. Model files exist
5. Port 8000 is free, plus your **correct LAN IP** (it skips the VirtualBox and Cloudflare WARP addresses)

Ends with `ALL GOOD` or a list of `[FAIL] … FIX: …` lines. Fix every FAIL before continuing (see §5).

### Step 2: Start it (pick one)

- **Run & debug (recommended):** press **`F5`**, or open the Run and Debug panel and pick **"Backend (FastAPI :8000)"**.
  You can set breakpoints in `main.py` / `inference.py`. Stop with **`Shift+F5`**.
- **Plain run:** task **`2. Start backend`**. Stop it with the trash-can icon on that terminal.

### Step 3: Confirm it's healthy
The terminal must show, in this order:

```
Supabase: connected OK
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:8000
```

If you see `!!! SUPABASE NOT CONNECTED` instead, stop the server and go to §5.
The server keeps running so you can read the error, but scans **will fail** until it's fixed.

Browser check: <http://localhost:8000/docs> should open the Swagger page.

> The backend now reads `backend/.env` on its own. The old `set -a && . ./.env` step is no longer needed.
> Before this change, forgetting that step was the main reason Supabase "sometimes wasn't connected".

---

## 3. Connect the phone

The app lets you change the server URL at runtime: **⚙ gear icon on the login screen**.
It is saved on the phone, so **changing the URL never needs an APK rebuild.**

### Option A: Same Wi-Fi (fastest)
1. Phone and PC on the **same Wi-Fi**.
2. Get the URL from the `1. Check setup` output, e.g. `http://192.168.0.183:8000`.
   (Manual: PowerShell `Get-NetIPAddress -InterfaceAlias Wi-Fi -AddressFamily IPv4`.
   Ignore `192.168.56.x` (VirtualBox) and `172.16.0.2` (the Cloudflare WARP VPN app, if it's switched on).)
3. **Test from the phone's browser first:** open `http://192.168.0.183:8000/docs`.
   - Page loads → the app will work.
   - Doesn't load → wrong IP, different Wi-Fi, the router blocks devices from seeing each other (common on college/guest Wi-Fi), or firewall. Use Option B.
4. App → ⚙ → paste the URL → Save → log in.

### Option B: ngrok (different network, mobile data, or blocked Wi-Fi)
1. Backend running (§2).
2. Run task **`3. ngrok tunnel`**.
3. URL is always **`https://purr-decline-paycheck.ngrok-free.dev`** (static domain).
4. App → ⚙ → paste that URL → Save.

### Login
Test account: `structvision.apptest@gmail.com` / `AppTest123!`

### Watching it work
Each phone action prints a line in the backend terminal:
```
"POST /scan HTTP/1.1" 200      ← upload accepted
"GET /scan/<id> HTTP/1.1" 200  ← app polling for the result
```
**No lines at all** means the phone isn't reaching the PC. Recheck the URL and network.

---

## 4. Build / install the APK

### Do I even need to rebuild?

| Change | Rebuild? |
|---|---|
| PC IP changed / switching Wi-Fi ↔ ngrok | **No.** Use the ⚙ gear icon |
| Backend Python code changed | **No.** Just restart the backend |
| ML model weights changed | **No.** Restart the backend |
| Flutter code in `project/app/lib` changed | **Yes** |
| Supabase project URL or publishable key changed | **Yes.** Edit `project/app/dart_defines.env` first |
| Want a different *default* server URL baked in | Yes (optional). Edit `DEFAULT_API_BASE` in `dart_defines.env` |

### Build
Run task **`APK: build release (+ copy to backend/static)`**. It takes 3–10 minutes; the first build is slower.

It runs, with `JAVA_HOME=F:\StructuralVision\tools\jdk-17`:
```powershell
F:\flutter\bin\flutter.bat build apk --release --dart-define-from-file=dart_defines.env
```
Output: `project/app/build/app/outputs/flutter-apk/app-release.apk` (~85 MB),
also copied to `project/backend/static/structural_vision_ar.apk`.

### Install on the phone (pick one)
- **USB:** enable Developer options → USB debugging, plug in, accept the prompt on the phone, run task **`APK: install on USB phone`**.
- **Download over the network:** with the backend running, open on the phone
  `http://<PC-IP>:8000/static/structural_vision_ar.apk` or
  `https://purr-decline-paycheck.ngrok-free.dev/static/structural_vision_ar.apk`
  (ngrok shows a warning page first; tap **Visit Site**). Allow "install unknown apps".
- **Copy the file** to the phone and tap it.

---

## 5. Troubleshooting

### Supabase not connected
Run task `1. Check setup` and match the FAIL:

| Check output | Cause | Fix |
|---|---|---|
| `SUPABASE_URL empty/placeholder` | `.env` missing or blank | Copy `.env.example` → `.env`, fill in from Supabase dashboard → Project Settings → API Keys |
| `cannot resolve …supabase.co` | No internet, or DNS blocked | Check internet; if the WARP VPN app is on, turn it off; try phone hotspot |
| `cannot reach Supabase` / timeouts | Internet, VPN, or college firewall | Turn any VPN (WARP etc.) off, try hotspot |
| Any other `HTTP 5xx`, or the dashboard shows "paused" | **Free-tier projects pause after ~7 days with no activity** | supabase.com/dashboard → project → **Restore project**. Wait 2–5 min, re-run check |
| `'scans': 401` | Wrong key in `.env` | `SUPABASE_SERVICE_KEY` must be the **secret** key (`sb_secret_…` / service_role), not the publishable one |
| `'scans': table missing` | Fresh project | Supabase → SQL Editor → paste and run `project/backend/schema.sql` |
| `JWKS fetch failed` | Same as unreachable/paused | See rows above. Without it, every phone request returns 401 |
| All OK in check, but backend says NOT CONNECTED | Backend started before internet was up, or a stale server | Stop it (`Shift+F5`) and start again |

### Other problems

| Symptom | Fix |
|---|---|
| Check says port 8000 already in use | A backend is already running (maybe an old terminal). Close it, or in PowerShell: `Get-NetTCPConnection -LocalPort 8000 -State Listen \| % { Stop-Process -Id $_.OwningProcess -Force }` |
| App: "Invalid API key" at login | APK built with the old legacy anon key (now **disabled** in Supabase). Rebuild the APK; `dart_defines.env` has the `sb_publishable_…` key |
| App: network/connection error at login | Phone offline, or Supabase paused (login goes straight to Supabase, not your PC) |
| Login works, scans fail/hang | Backend unreachable → ⚙ URL wrong, or backend stopped. Check the backend terminal for request lines |
| Backend terminal shows `401` | Phone session expired → log out and in. If it keeps happening, check JWKS in the preflight check |
| Scan stuck "pending" | Traceback in the backend terminal. Inference crashed |
| APK build: "Unsupported class file major version" / Java errors | Built outside the task with Java 8. Use the task, or set `$env:JAVA_HOME="F:\StructuralVision\tools\jdk-17"` first |
| APK build: Gradle out of memory | Close Chrome/other heavy apps (`gradle.properties` asks for 8 GB) |
| `adb: no devices` | Replug USB, accept the "Allow USB debugging" prompt, set USB mode to File Transfer |
| Worked yesterday, not today | New Wi-Fi IP (update ⚙), or Supabase paused (Restore) |

### Logs
- **Backend:** the terminal it runs in.
- **Phone (USB):** task `Phone: logcat (flutter)`.
- **Data:** Supabase dashboard → Table Editor → `scans`, `crack_detections`; Storage → `scan-images`.

---

## 6. Daily checklist

```
[ ] VS Code → Open Folder F:\StructuralVision
[ ] Task "1. Check setup" → ALL GOOD
[ ] F5 → "Supabase: connected OK" + "Application startup complete"
[ ] Phone browser opens http://<IP>:8000/docs   (or start ngrok task)
[ ] App ⚙ gear → URL saved → login
[ ] Test scan with a demo_kit photo → result in a few seconds
```
