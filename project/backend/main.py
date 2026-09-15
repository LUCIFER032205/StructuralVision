"""
main.py — Structural Vision AR backend.

POST /scan          multipart image + JWT  -> {scan_id, status: "pending"}
GET  /scan/{id}     JWT                     -> {status, result?}   (Flutter polls every 2s)
POST /scan/{id}/measurement  JWT {length_cm} -> scan with measured (JBDPA/BRE 251) risk

All endpoints require Authorization: Bearer <supabase_jwt>.
"""
import os
from pathlib import Path

# Load backend/.env ourselves so the server works however it's launched
# (VS Code, plain terminal, no `set -a`). Real env vars still win.
_ENV = Path(__file__).resolve().parent / ".env"
if _ENV.exists():
    for _line in _ENV.read_text(encoding="utf-8").splitlines():
        _k, _sep, _v = _line.strip().partition("=")
        if _sep and not _k.startswith("#"):
            os.environ.setdefault(_k.strip(), _v.strip().strip('"').strip("'"))

from contextlib import asynccontextmanager
from functools import lru_cache
from fastapi import FastAPI, UploadFile, File, Form, BackgroundTasks, HTTPException, Depends
from fastapi.responses import Response
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from inference import run_scan, load_models, measured_risk, width_from_measurement
from auth import current_user
import db
import overlay
import report


@asynccontextmanager
async def lifespan(app: FastAPI):
    load_models()  # pay the model-load cost once at boot, not on first request
    try:
        db._conn().table("scans").select("id").limit(1).execute()
        print("Supabase: connected OK")
    except Exception as e:
        print(f"\n!!! SUPABASE NOT CONNECTED: {e!r}\n!!! Run: python check_setup.py  (see RUN_GUIDE.md)\n")
    db.ensure_bucket()
    yield


app = FastAPI(title="Structural Vision AR", lifespan=lifespan)
app.mount("/static", StaticFiles(directory="static"), name="static")


def _process(scan_id: str, image_bytes: bytes, prev_scan_id: str | None = None,
             component_type: str | None = None):
    try:
        result = run_scan(image_bytes, component_type)
        if prev_scan_id:
            prev = db.get_scan_unauth(prev_scan_id)
            if prev and prev.get("detections"):
                from inference import diff_detections
                result["detections"] = diff_detections(prev["detections"], result["detections"])
        try:
            image_url = db.upload_image(scan_id, image_bytes)
        except Exception:
            image_url = None  # history item just won't have a photo
        db.finish_scan(scan_id, result, image_url)
    except Exception as e:
        db.fail_scan(scan_id, str(e))


@app.post("/scan")
async def create_scan(
    bg: BackgroundTasks,
    image: UploadFile = File(...),
    prev_scan_id: str | None = Form(None),
    # The component the user picked before capture. Optional so an older client
    # build still scans (component just stays unset); the current app always sends it.
    component_type: str | None = Form(None),
    user_id: str = Depends(current_user),
):
    image_bytes = await image.read()
    scan_id = db.create_scan(user_id)
    bg.add_task(_process, scan_id, image_bytes, prev_scan_id, component_type)
    return {"scan_id": scan_id, "status": "pending"}


@app.get("/scans")
async def list_scans(user_id: str = Depends(current_user)):
    return db.list_scans(user_id)


@app.get("/scan/{scan_id}")
async def get_scan(scan_id: str, user_id: str = Depends(current_user)):
    scan = db.get_scan(scan_id, user_id)
    if scan is None:
        raise HTTPException(404, "scan not found")
    return scan


class Measurement(BaseModel):
    length_cm: float = Field(gt=0, le=1000)   # AR two-tap distance along the crack


@app.post("/scan/{scan_id}/measurement")
async def add_measurement(scan_id: str, m: Measurement, user_id: str = Depends(current_user)):
    """Physical scale from AR -> crack width -> published damage grade.
    Replaces the preliminary pixel-area risk on the stored scan and its report."""
    scan = db.get_scan(scan_id, user_id)
    if scan is None:
        raise HTTPException(404, "scan not found")
    if scan["status"] != "done":
        raise HTTPException(409, f"scan is {scan['status']}")
    width_mm, crack_type = width_from_measurement(m.length_cm, scan.get("detections") or [])
    if width_mm is None:
        raise HTTPException(422, "no measurable crack in this scan")
    graded = measured_risk(width_mm, scan.get("component_type"), crack_type)
    db.set_measurement(scan_id, width_mm, graded)
    _overlay_glb.cache_clear()   # overlay label colour follows the scan risk
    return db.get_scan(scan_id, user_id)


@app.get("/scan/{scan_id}/overlay.glb")
async def get_overlay(scan_id: str):
    """AR crack-overlay quad. No JWT: the AR plugin's native GLB loader can't
    send headers; scan_id is an unguessable UUID (same model as the image bucket)."""
    return Response(_overlay_glb(scan_id), media_type="model/gltf-binary")


@lru_cache(maxsize=64)
def _overlay_glb(scan_id: str) -> bytes:
    # The AR plugin re-requests the GLB on every load attempt; without a cache
    # each hit costs ~4s of Supabase round-trips (scan row + image download).
    scan = db.get_scan_unauth(scan_id)
    if scan is None or scan["status"] != "done":
        raise HTTPException(404, "scan not found")
    try:
        image_bytes = db.download_image(scan_id)
    except Exception:
        raise HTTPException(404, "scan image not stored")
    return overlay.build_overlay_glb(
        image_bytes,
        scan.get("detections") or [],
        scan.get("component_type"),
        scan.get("risk_level"),
    )


@app.get("/scan/{scan_id}/report")
async def get_report(scan_id: str, user_id: str = Depends(current_user)):
    scan = db.get_scan(scan_id, user_id)
    if scan is None:
        raise HTTPException(404, "scan not found")
    if scan["status"] != "done":
        raise HTTPException(409, f"scan is {scan['status']}")
    try:
        image_bytes = db.download_image(scan_id)
    except Exception:
        raise HTTPException(404, "scan image not stored")
    pdf = report.build_pdf(scan, image_bytes)
    return Response(pdf, media_type="application/pdf", headers={
        "Content-Disposition": f'attachment; filename="scan_{scan_id[:8]}.pdf"'})
