# Git Tracking Log — StructuralVision

**Repo:** https://github.com/LUCIFER032205/StructuralVision  
**Branch:** master  
**Last pushed:** 2026-08-13

---

## What's tracked (pushed to GitHub)

### Root
| File | Notes |
|---|---|
| `.gitignore` | Excludes secrets, datasets, weights, build artifacts |
| `README.md` | Setup instructions for backend + Flutter app |
| `TODO.md` | Project task list |
| `architecture_improvements.md` | Architecture notes |
| `StructuralVisionAR_DraftPaper_v2.docx` | Draft research paper |
| `StructuralVisionAR_DraftPaper_v2.pdf` | PDF version of draft paper |
| `StructuralVisionAR_Team_Scripts.docx` | Team scripts doc |

### docs/
| File | Notes |
|---|---|
| `docs/superpowers/specs/2026-08-07-burst-capture-design.md` | Burst capture feature spec |

### presentation/
| File | Notes |
|---|---|
| `presentation/StructuralVision_AR_Demo.pptx` | Main demo presentation |
| `presentation/build_deck.js` | Deck build script |
| `presentation/package.json` | Node package config |
| `presentation/package-lock.json` | Node lockfile |
| `presentation/cropped/*.png` | 6 cropped slide screenshots |
| `presentation/qa/*.PNG` | 9 QA slide screenshots |
| `presentation/shots/*.png` | App screenshots for slides |

### project/app/ (Flutter)
| File | Notes |
|---|---|
| `lib/config.dart` | ⚠️ Keys use `String.fromEnvironment()` — pass via `--dart-define` |
| `lib/main.dart` | App entry point |
| `lib/models.dart` | Data models |
| `lib/scan_api.dart` | API client |
| `lib/theme.dart` | App theme |
| `lib/screens/*.dart` | All active screens (ar, batch, camera, history, login, result) |
| `lib/screens/_backup/*.dart` | Backup versions of screens |
| `lib/_backup_main.dart` | Backup main |
| `pubspec.yaml` | Flutter dependencies |
| `analysis_options.yaml` | Dart lint config |
| `android/` | Android build config (no local.properties or key.properties) |
| `test/` | Unit + contract tests |

### project/backend/ (FastAPI)
| File | Notes |
|---|---|
| `.env.example` | Template for secrets — copy to `.env` and fill in |
| `main.py` | FastAPI app entry |
| `auth.py` | Auth logic |
| `db.py` | Database helpers |
| `inference.py` | ML inference |
| `overlay.py` | AR overlay generation |
| `report.py` | Report generation |
| `requirements.txt` | Python dependencies |
| `schema.sql` | Supabase DB schema |
| `static/marker_*.glb` | AR 3D marker assets (high/medium/low) |

### project/models/
Nothing tracked — `.pt` weight files are excluded (too large). Download separately.

### project/demo_kit/
| File | Notes |
|---|---|
| `README.md` | Demo kit instructions |
| `high_1.jpg`, `high_2.jpg` | High severity test images |
| `medium_1.jpg`, `medium_2.jpg` | Medium severity test images |
| `low_1.jpg`, `low_2.jpg` | Low severity test images |

### project/docs/
| File | Notes |
|---|---|
| `device-test-checklist.md` | Device testing checklist |
| `model_evolution_report.md` / `.pdf` | Model evolution report |
| `model_report_assets/*.jpg` | Heatmap and result images for report |
| `remote-demo-runbook.md` | Runbook for remote demos |
| `superpowers/specs/2026-07-12-structural-vision-ar-design.md` | Original design spec |
| `walkthrough-guide.md` | User walkthrough guide |

### project/ (scripts)
| File | Notes |
|---|---|
| `download_column_images.py` | Dataset download script |
| `export_model2_onnx.py` | ONNX export script |
| `prepare_datasets.py` | Dataset preparation |
| `train_model1_crack.ipynb` | Crack model training notebook |
| `train_model2_classifier.py` | Classifier training script |
| `zip_dataset.py` | Dataset zip utility |
| `structural_vision_ar_context__.md` | Project context doc |
| `structural_vision_ar_dev_plan.md` | Dev plan |

---

## What's NOT in git (intentionally excluded)

| What | Why |
|---|---|
| `project/backend/.env` | Contains live Supabase keys — keep local only |
| `datasets/` | 140k+ training images — too large, download separately |
| `project/models/*.pt` | ML weight files — too large (~50 MB each) |
| `ngrok.exe` | Binary tool, not source code |
| `project/backend/static/structural_vision_ar.apk` | 85 MB APK — use GitHub Releases if needed |
| `project/app/build/` | Flutter build artifacts |
| `project/app/android/.gradle/` | Gradle cache |
| `node_modules/` | JS dependencies, install via `npm install` |
| `__pycache__/`, `.venv/` | Python cache and virtualenv |
| `.claude/` | Claude Code session data |

---

## How to update the repo

After making changes locally:

```bash
cd /d F:\StructuralVision
git add .
git status          # review what's staged — make sure no .env or .pt files
git commit -m "your message here"
git push
```

If you add a new file that should be excluded, add it to `.gitignore` before running `git add .`.

---

## Key things to remember

- **Never commit `.env`** — it has your live Supabase service key
- **Supabase keys in the Flutter app** go via `--dart-define`, not hardcoded in `config.dart`
- **Model weights** (`.pt`) are gitignored — if you train a new model, share the file out-of-band
- The APK in `project/backend/static/` is already in git from the first push (85 MB warning) — for future APK updates, use GitHub Releases instead
