# Device Test Checklist — Structural Vision AR

Phone must be ARCore-capable and on the **same Wi-Fi** as the PC.

## 1. Verify LAN IP (do this first)
```
ipconfig
```
Look for the Wi-Fi adapter's IPv4 (ignore 192.168.56.1 — that's VirtualBox).
Expected: `172.16.14.69`. If it changed:
- Update `apiBase` in `app/lib/config.dart`
- Rebuild: `cd app && JAVA_HOME="C:\Program Files\Eclipse Adoptium\jdk-21.0.7.6-hotspot" F:/flutter/bin/flutter build apk --debug`

## 2. Start backend (Git Bash)
```
cd F:/Major_project/Major_project/backend
set -a && . ./.env && set +a
uvicorn main:app --host 0.0.0.0
```

## 3. Windows Firewall
Allow inbound TCP 8000 (or temporarily disable firewall for the test):
```
netsh advfirewall firewall add rule name="StructVision8000" dir=in action=allow protocol=TCP localport=8000
```
(Run as admin. Delete after: `netsh advfirewall firewall delete rule name="StructVision8000"`)

## 4. Connectivity check from phone browser
- `http://172.16.14.69:8000/docs` → FastAPI docs page loads
- `http://172.16.14.69:8000/static/marker_high.glb` → downloads ~25KB file

## 5. Install APK
APK: `app/build/app/outputs/flutter-apk/app-debug.apk`
- `adb install app/build/app/outputs/flutter-apk/app-debug.apk`, or copy to phone and open.

## 6. Full flow test
Login: `structvision.apptest@gmail.com` / `AppTest123!`

1. Login succeeds
2. Camera opens → capture a real wall/beam/column
3. Uploads, polls (~2s intervals), lands on result screen
4. Result screen: photo + crack polygon overlay (if cracks) + component label + risk badge
5. Check backend logs / Supabase: new row in `scans` (+ `crack_detections` if cracks)

## 7. AR screen (the untested piece)
1. Open AR view from result screen
2. Move phone slowly → plane dots/mesh appear on surfaces
3. Tap a detected plane → risk-colored pin marker pins at that spot (red=HIGH, orange=MEDIUM, green=LOW)
4. Risk/component badge overlay visible
5. Walk around → marker stays anchored

## Troubleshooting
- "Invalid API key" on login → APK built with stale config.dart; rebuild.
- Upload hangs → firewall or wrong IP; redo steps 1, 3, 4.
- AR marker never appears → check `/static/marker_high.glb` loads in phone browser (step 4).
