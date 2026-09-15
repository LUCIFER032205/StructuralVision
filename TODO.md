# Structural Vision AR — TODO (updated 2026-09-15)

Plan to finish: `project/docs/finish_plan.md` (target 2026-09-30).

## Done 2026-09-15
- All app + backend work committed; `.gitignore` fixed (apk rule was quoted and never matched; `kaggle_tomo/` now ignored).
- App: confidence floor 0.5 → 0.4 in the result-screen outline shading (matches backend conf 0.4).
- Backend: duplicate crack masks merged (NMS iou 0.45). v4 was drawing 2 masks on one crack, doubling area and risk.
- Risk thresholds re-fit 0.10/0.25 → 0.03/0.07 on demo_kit (see `project/demo_kit/README.md`).
- Rescan of all 63 stored app scans with v4: all 8 v2 false alarms (curtains, bag, laptop) are now clean;
  6 remaining false alarms are straight architectural edges (table edge, beam edges, projector, TV).

## Tonight — one round of device testing (Vivo Y200)

Setup: VS Code task `1. Check setup` → `2. Start backend` → (other network) `3. ngrok tunnel`.
Rebuild the APK first (`APK: build release`); the committed app change is not in the current APK.

### A. Detection on real surfaces — the numbers for the paper
Scan each, write down: cracks found (y/n), risk shown, correct? (y/n)
- [ ] 10 real cracks (walls, columns, beams, ceiling) — pick component correctly each time
- [ ] 10 NON-cracks that look like cracks: table edge, beam/ceiling edge, wall corner, door frame,
      tile grout, cable on wall, curtain fold, bag seam, projector/TV edge, shadow line
- [ ] Same real crack scanned as column vs wall vs ceiling → risk should drop column > wall > ceiling
- [ ] demo_kit high_1 / medium_1 / low_1 off a screen as column → HIGH / MEDIUM / LOW

### B. App flow
- [ ] Component sheet → capture → result in 1 tap after picking component
- [ ] Tap a crack → "NN% confident"; weak crack draws thinner/fainter
- [ ] Pinch-zoom on the result photo
- [ ] Clean wall → "No cracks detected" empty state
- [ ] History + batch screens open, old scans load

### C. AR (still untested since the 7/21 build)
- [ ] Dots appear immediately + "sweep slowly" hint, then tap-to-place
- [ ] Overlay label risk == result screen risk
- [ ] Two-tap measure → risk switches to "measured" grade (JBDPA/BRE251)
- [ ] Vertical-plane toggle (may SIGSEGV — note it if so)

### D. Site preview (3D building) — only in an APK built after commit 9ebf26e
- [ ] Building icon on camera screen → floor dots → tap → tower appears (~40 cm)
- [ ] "Life-size" → 20 m tower; "Miniature" → back; refresh icon → place again
- [ ] Back to camera → scan → crack AR still works (camera handover)

Save failures as screenshots + scan id. Anything wrong gets fixed tomorrow, before new features.

## After testing (only if tonight is clean)
- Paper + `model_evolution_report.md`: v2 → v3 rejected → v4, image-level accuracy, NaN investigation,
  dataset 9,816 images, duplicate-mask + real-photo false-alarm findings.
- Video scan mode, plugin fork / auto-place, gap → drip mapping: cut unless the paper is done early.

## Reference
- Run backend: `cd project/backend && /c/Python314/python -m uvicorn main:app --host 0.0.0.0`
- Tunnel: `F:\StructuralVision\tools\ngrok.exe http 8000` → `https://purr-decline-paycheck.ngrok-free.dev`
- APK share link: Supabase bucket `app-releases` (re-upload after rebuilds, arm64 split only)
