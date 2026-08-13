# Wednesday demo — remote-phone runbook

The app on any phone can reach the backend at home through an ngrok tunnel.
The APK no longer hardcodes the server: the login screen has a ⚙ gear icon to
set the server URL at runtime.

## Before leaving home (or ask whoever is at the PC)

```bash
# 1. Start the backend
cd F:\Major_project\Major_project\backend
set -a && . ./.env && set +a
/c/Python314/python -m uvicorn main:app --host 0.0.0.0 --port 8000

# 2. Start the tunnel (separate terminal)
F:\StructuralVision\ngrok.exe http 8000
```

The tunnel URL is **always** `https://purr-decline-paycheck.ngrok-free.dev`
(static free ngrok domain — same every restart, no re-pasting needed).
PC must stay on with both processes running during the demo.

## On the friend's phone (one-time setup)

1. Download the APK: open
   `https://purr-decline-paycheck.ngrok-free.dev/static/structural_vision_ar.apk`
   in the phone browser (~85 MB). ngrok shows a "You are about to visit…"
   warning page first — tap **Visit Site** (browser-only; the app's API calls
   are unaffected). Allow "install from unknown sources" when prompted.
2. Open the app → tap the **⚙ gear icon** on the login screen → paste
   `https://purr-decline-paycheck.ngrok-free.dev` → Save. (Persists across app restarts.)
3. Sign in: `structvision.apptest@gmail.com` / `AppTest123!`
4. Use gallery upload with the demo_kit images (copy them to the phone), or
   point the camera at printed ones.

AR needs an ARCore-capable phone (most 2020+ Androids —
check https://developers.google.com/ar/devices).

## Notes

- Scan history photos load from Supabase directly — they work anywhere.
- The AR overlay/markers load through the tunnel URL — also fine (HTTPS).
- If the URL somehow changed (shouldn't — it's static), just re-open the
  gear dialog and paste the new one.
