# Structural Vision AR — TODO (written 2026-07-27, evening)

## Done today
- Consolidated everything into `F:\StructuralVision\` (project + datasets), all paths fixed, backend self-check passes.
- **#1 AR load UX**: feature points shown immediately + "sweep slowly" spinner hint until first plane detected (`ar_screen.dart`). Release APK rebuilt, copied to backend/static AND uploaded to Supabase share link.

## Tomorrow — in order

### 1. Device-test the new AR onboarding (Vivo Y200) — 15 min
- Install new APK (tunnel link or adb), scan → AR.
- Expect: dots immediately, spinner + sweep hint, then tap-to-place prompt.
- Also still untested from 7/21 build: vertical-plane toggle (may SIGSEGV — horizontalAndVertical did), two-tap measure, severity labels in overlay.

### 2. Auto-place stopgap: crosshair UX — ~30 min
- Plugin has NO programmatic hit-test → true auto-place blocked without forking.
- Stopgap: on first plane detected, pulsing crosshair at screen center + "tap here" hint. ~20 lines in `ar_screen.dart`.

### 3. Paint crack vs structural crack (guide's idea — it's legit, not BS)
- Cheapest first: **heuristic on existing masks** — width / length / straightness / branching from crack polygons. Craze web = cosmetic, long wide directional = structural. Flag on result screen. No retraining, no new data.
- Later: physical width from AR measure as extra signal (<1mm → cosmetic-leaning).
- Much later: trained classifier on crack crops (needs labeling few hundred crops).

### 4. Video scan mode (#2 from evening-todo)
- Client-side lazy version: record ~10s → sample 5-8 frames → fire existing `/scan` per frame → merge detections (IoU dedupe). No new backend endpoint.

### 5. Plugin fork (unlocks real auto-place + #3 drip mapping)
- Copy `ar_flutter_plugin_2` → `app/plugins/`, local path dep in pubspec.
- Add Kotlin method channel: `hitTestFromScreen(x,y)` → `frame.hitTest()` → pose.
- Then: auto-place overlay on first plane; later ray-cast for gap→drip-spot mapping.
- Risk: native code on the SIGSEGV-prone Vivo — test incrementally.

### 6. Gap → drip-spot mapping (the guide's "wow" feature)
- Needs: #4 (video helps catch gaps) + #5 (ray-cast down from gap to floor plane).
- Also needs gap/seam training data eventually.

## Background / parallel
- Model 1 retrain toward mAP50 0.90 (GPU task, data-bound — more labeled data / TTA / harder negatives from scan history).
- Duplicate-mask dedup in `inference.py` (2 detections of same crack inflate area ratio — scan 0310b12e case).
- Wall-scan OOD misclassification (cluttered wall → "ceiling @0.98") — scan guides first, then maybe user-override on class.

## Reference
- Guide feedback details: `project\docs\evening-todo.md`
- Run backend: `cd project/backend && /c/Python314/python -m uvicorn main:app --host 0.0.0.0`
- Tunnel: `F:\StructuralVision\ngrok.exe http 8000` → always `https://purr-decline-paycheck.ngrok-free.dev`
- APK share link: Supabase bucket `app-releases` (re-upload after rebuilds, arm64 split only)
