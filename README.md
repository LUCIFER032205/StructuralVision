# StructuralVision

AR-powered structural defect detection app. Point your phone at a wall, beam, or slab and get real-time crack and spalling annotations overlaid via augmented reality.

**Stack:** Flutter (mobile) · FastAPI (backend) · YOLOv8 (ML models) · Supabase (auth + database)

---

## Project layout

```
project/
├── app/          # Flutter mobile app (Android)
├── backend/      # FastAPI inference + auth server
└── models/       # YOLOv8 model configs (weights downloaded separately)
docs/             # Architecture diagrams, research notes
datasets/         # Training images — NOT in git (download separately)
```

---

## Setup

### 1 · Backend

```bash
cd project/backend
python -m venv .venv && source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt

# Copy the example env file and fill in your Supabase credentials
cp .env.example .env
# Edit .env with your SUPABASE_URL, SUPABASE_SERVICE_KEY, SUPABASE_JWT_SECRET

uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

### 2 · Flutter app

```bash
cd project/app
flutter pub get

# Run with your own credentials injected at build time
flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key \
  --dart-define=DEFAULT_API_BASE=http://YOUR_PC_LAN_IP:8000
```

> Get `SUPABASE_URL` and `SUPABASE_ANON_KEY` from Supabase → Project Settings → API.  
> For a physical device use your PC's LAN IP (`ipconfig`). For the emulator use `http://10.0.2.2:8000`.

### 3 · Model weights

The `.pt` weight files are excluded from git (binary, ~50 MB each). Download them from the shared drive link in the project docs, then place them in `project/models/`.

---

## Environment variables reference

| Variable | Where | Description |
|---|---|---|
| `SUPABASE_URL` | `.env` + `--dart-define` | Supabase project URL |
| `SUPABASE_SERVICE_KEY` | `.env` only | Service-role key (backend only — never in the app) |
| `SUPABASE_JWT_SECRET` | `.env` only | JWT signing secret |
| `SUPABASE_ANON_KEY` | `--dart-define` | Publishable anon key for the Flutter app |
| `DEFAULT_API_BASE` | `--dart-define` | Base URL of the FastAPI server |
