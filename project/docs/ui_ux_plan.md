# StructuralVision AR — UI/UX Improvement Plan

*Written 2026-09-12, for the 7pm session (runs alongside the v4 medium training.)*

---

## 1. What's already good — don't touch it

The theme is not the problem. `project/app/lib/theme.dart` already has:

- A real token system (`AppColors`, `AppTextStyles`, `kCardRadius/kButtonRadius/kPagePadding`) — no hardcoded hex scattered across screens.
- Dark-first, which matches both the product (camera viewfinder) and user preference (~80% prefer dark when offered).
- Amber accent on deep slate — construction-appropriate, and it reads as "warning-aware" without being alarmist.
- 48dp minimum button heights already set on filled/outlined buttons.

**Conclusion: this is not a restyle job.** The gaps are interaction, feedback, and field-usability — not colour choice. Anyone proposing a new palette is solving the wrong problem.

---

## 2. What the research says

Sources at the bottom. The consistent themes for a tool of this type:

| Finding | Why it matters here |
|---|---|
| 48×48dp minimum targets, bigger for gloved hands | Inspectors wear gloves; a missed shutter tap in the field is a re-climb |
| Sunlight readability decides adoption | "If the app requires precise tapping or squinting at small text, it gets abandoned quickly by field crews" |
| Reduce taps aggressively; context-aware controls | Every modal before a capture is friction repeated on every single scan |
| Confidence indicators for AI output | Users need to know when to trust vs verify — critical when the model sits around 0.675 mask mAP50 |
| Thumb reach zone / one-handed use | Inspector's other hand is on a ladder, rail, or torch |
| Scanning animation raises perceived quality | A sweep line before results makes the wait feel purposeful |
| Offline-first is table stakes for field apps | Basements and sites have no signal; a failed upload must not lose the scan |

---

## 3. Prioritised backlog

### P0 — correctness and field-blocking (do these first)

**P0.1 — `textMuted` fails contrast (verified, not estimated)**
`AppColors.textMuted #484F58` on `bg #0D1117` = **2.28:1**. WCAG needs 4.5:1 for body text. It's used by `AppTextStyles.label` — which is **11px** — and that style labels the CRACKS / AREA stat chips on the result screen. So the smallest text in the app is also the lowest contrast, on a screen used outdoors.
*Fix:* lift `textMuted` to ≈`#7D8590` (≈4.6:1), raise `label` to 12px, `bodySm` to 13px.
*Effort: 15 min. Touches theme.dart only.*

**P0.2 — No press feedback or semantics on the camera controls**
`camera_screen.dart:510` (`_ShutterButton`) and `:556` (`_SideButton`) are bare `GestureDetector`s. No ripple, no opacity change, no haptic, no accessibility label. With gloves and no tactile response, users can't tell whether the shutter fired.
*Fix:* wrap in `InkWell`/`Semantics`, add `HapticFeedback.mediumImpact()` on capture.
*Effort: 30 min.*

**P0.3 — Offline scans are lost**
A failed upload shows a snackbar and the photo is gone. In a basement with no signal, that's the whole inspection lost.
*Fix:* queue captures locally, retry when connectivity returns, show a "3 pending" chip.
*Effort: half a day — the largest item here, and the one most likely to decide real-world adoption.*

### P1 — high value, contained

**P1.1 — Kill the component modal before every capture**
`camera_screen.dart:66` opens `ComponentSelectSheet` *before* each shot. That's a modal on the critical path, every time.
*Fix:* persistent chip in the viewfinder showing the current component (e.g. "Beam ▾"), remembered from the last scan, tappable to change. Cuts a scan from 3 taps to 1.
*Effort: 1–2 h.*

**P1.2 — Show detection confidence**
`CrackDetection` already carries `confidence`, and the result UI never shows it. This is the single biggest trust gap, and it pairs with the ML plan's hard-negative mining: let the user flag a false positive, and that flagged image becomes training data.
*Fix:* per-detection confidence on tap, plus colour-weighted overlay strokes (thick/saturated = high confidence, thin/desaturated = low), which is exactly the scanner-app pattern.
*Effort: 2–3 h including the flagging flow.*

**P1.3 — Pinch-zoom the annotated result**
`result_screen.dart:82` uses a plain `FittedBox`. A hairline crack on a 1024px photo shown on a 6" phone is unreadable, and there is no way to zoom.
*Fix:* wrap in `InteractiveViewer`. Near-free win.
*Effort: 20 min.*

**P1.4 — Torch toggle and tap-to-focus**
No flash control and no tap-to-focus in a camera-first inspection tool. Stairwells, basements, and undersides of beams are dark, and autofocus hunts on flat concrete.
*Fix:* torch button in the control bar; tap-to-focus with a focus reticle.
*Effort: 1–2 h.*

**P1.5 — Empty state for zero detections**
Currently a clean wall returns the same layout with zeros in the chips. "No cracks found" deserves an explicit, reassuring state — it's a *result*, not an absence of one.
*Effort: 30 min.*

**P1.6 — Capture resolution**
`camera_screen.dart:49` uses `ResolutionPreset.medium` (~720p) while the model trains and infers at 1024px. Hairline cracks may be lost before inference even starts. Not styling, but it caps result quality.
*Fix:* `ResolutionPreset.high`, measure the upload-size and latency cost.
*Effort: 10 min to change, 30 min to verify.*

### P2 — polish, when the above is done

- **Progress + cancel during analysis.** `_ProcessingOverlay` is a blocking spinner with no way out. Add staged text and a cancel button.
- **Scan sweep animation** over the frozen frame while analysing — cheap, and research says it raises perceived output quality.
- **Respect reduced motion.** `_PulsingDot` (`camera_screen.dart:396`) repeats forever regardless of `MediaQuery.disableAnimations`.
- **Voice notes** on a result — inspectors have their hands full. Cited repeatedly in field-app research.
- **De-dupe `riskColors`** in `result_screen.dart:12`; it restates what `RiskBadge` already owns.

---

## 4. Open decisions for 7pm

1. **Sunlight mode?** Dark is right for the viewfinder, but dark UI is the *harder* one to read in direct sun. Options: keep dark-only and just raise contrast/weight (cheap), or add a high-contrast light mode for the result/history screens (a day's work). My lean: raise contrast first, measure on the Vivo outdoors, only then decide.
2. **Who is the actual user?** A certified inspector, or a student demoing the project? Optimising for gloved field use versus for a viva demo pulls in different directions. This changes the ordering above more than anything else.
3. **Is the demo deadline before or after the field polish?** If a presentation is close, P1.2 (confidence) and P1.3 (zoom) are the visible wins; P0.3 (offline) is invisible in a demo but decisive in the field.

---

## 5. Suggested first slice (about 2 hours)

P0.1 + P0.2 + P1.3 + P1.5. All four are small, none of them touch the backend or the model, and together they fix the contrast failure, make the camera feel responsive, let users actually inspect the result, and stop the zero-crack case from looking broken.

---

## Sources

- [Mobile App Design Trends 2026 — Muzli](https://muz.li/blog/whats-changing-in-mobile-app-design-ui-patterns-that-matter-in-2026/)
- [9 Mobile App Design Trends for 2026 — UX Pilot](https://uxpilot.ai/blogs/mobile-app-design-trends)
- [13 Mobile App UI/UX Design Trends to Watch in 2026 — Design Studio](https://www.designstudiouiux.com/blog/mobile-app-ui-ux-design-trends/)
- [Field Inspection App Development Guide 2026 — Simpalm](https://www.simpalm.com/blog/field-inspection-app-development-guide)
- [Site inspection tools field teams will actually use — DroneDeploy](https://www.dronedeploy.com/blog/how-to-find-site-inspection-tools-that-field-teams-will-actually-use)
- [Improving UX for Field Service Technicians — Software Testing Magazine](https://www.softwaretestingmagazine.com/knowledge/mobile-qa-improving-ux-for-field-service-technicians/)
- [Making the iPhone Camera Feel Like a Document Scanner — BoardSnap](https://boardsnap.ai/blog/making-the-camera-feel-like-a-document-scanner/)
- [Confidence Score — AI UX Playground](https://aiuxplayground.com/pattern/confidence-score/)
- [Confidence Visualization in AI — AI Design Patterns](https://www.aiuxdesign.guide/patterns/confidence-visualization)
