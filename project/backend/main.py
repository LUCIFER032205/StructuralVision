"""
main.py — Structural Vision AR backend.

POST /scan          multipart image + JWT  -> {scan_id, status: "pending"}
GET  /scan/{id}     JWT                     -> {status, result?}   (Flutter polls every 2s)
POST /scan/{id}/cracks/{crack_id}/measurement  JWT {length_cm} -> that crack graded (JBDPA/BRE 251)
POST /scan/{id}/cracks/{crack_id}/status       JWT {status}    -> skipped | not_crack | todo

All endpoints require Authorization: Bearer <supabase_jwt>.
"""
import io
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
from typing import Literal
from functools import lru_cache
from fastapi import FastAPI, UploadFile, File, Form, BackgroundTasks, HTTPException, Depends
from fastapi.responses import Response
from fastapi.staticfiles import StaticFiles
import numpy as np
from PIL import Image
from pydantic import BaseModel, Field

from inference import (run_scan, load_models, crack_measurement, summarize,
                       implausible_measurement)
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
    length_cm: float = Field(gt=0, le=1000)   # AR two-tap or tape, along the crack


class CrackStatus(BaseModel):
    status: Literal["skipped", "not_crack", "todo"]


def _crack(scan_id: str, crack_id: str, user_id: str) -> tuple[dict, dict]:
    scan = db.get_scan(scan_id, user_id)
    if scan is None:
        raise HTTPException(404, "scan not found")
    if scan["status"] != "done":
        raise HTTPException(409, f"scan is {scan['status']}")
    det = next((d for d in scan.get("detections") or [] if d["id"] == crack_id), None)
    if det is None:
        raise HTTPException(404, "crack not found")
    return scan, det


def _resummarize(scan: dict, user_id: str) -> dict:
    db.update_scan(scan["id"], summarize(scan["detections"], scan.get("component_type")))
    _overlay_glb.cache_clear()   # overlay drops dismissed cracks, label follows risk
    return db.get_scan(scan["id"], user_id)


@app.post("/scan/{scan_id}/cracks/{crack_id}/measurement")
async def measure_crack(scan_id: str, crack_id: str, m: Measurement,
                        user_id: str = Depends(current_user)):
    """Physical length of one crack -> its width -> its published grade; the
    wall takes the worst graded crack."""
    scan, det = _crack(scan_id, crack_id, user_id)
    gray = None
    try:
        photo = Image.open(io.BytesIO(db.download_image(scan_id)))
        # Taps that land on the floor behind a wall imply an absurd frame size.
        reason = implausible_measurement(m.length_cm, det.get("length_px") or 0, photo.width)
        if reason:
            raise HTTPException(422, reason)
        gray = np.asarray(photo.convert("L"))
    except HTTPException:
        raise
    except Exception:
        pass   # photo unavailable: grade off the mask alone
    meas = crack_measurement(m.length_cm, det, scan.get("component_type"), gray)
    if meas is None:
        raise HTTPException(422, "this crack has no measurable length")
    db.update_detection(crack_id, {"status": "measured", "measurement": meas})
    det.update(status="measured", measurement=meas)
    return _resummarize(scan, user_id)


@app.post("/scan/{scan_id}/cracks/{crack_id}/status")
async def set_crack_status(scan_id: str, crack_id: str, s: CrackStatus,
                           user_id: str = Depends(current_user)):
    """Skip a crack, dismiss it as not a crack, or reset it to to-do."""
    scan, det = _crack(scan_id, crack_id, user_id)
    status = None if s.status == "todo" else s.status
    db.update_detection(crack_id, {"status": status, "measurement": None})
    det.update(status=status, measurement=None)
    return _resummarize(scan, user_id)


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
        [d for d in scan.get("detections") or [] if d.get("status") != "not_crack"],
        scan.get("component_type"),
        scan.get("risk_level"),
    )


@app.get("/report")
async def get_batch_report(ids: str, user_id: str = Depends(current_user)):
    """One PDF for a whole inspection: ?ids=uuid,uuid,... in capture order.
    Summary table (component + risk per photo) then a page per photo."""
    scan_ids = [i for i in ids.split(",") if i]
    if not scan_ids:
        raise HTTPException(400, "no scan ids")
    # Every captured photo gets a row, even a failed or still-pending one:
    # a report that silently drops them would under-count the inspection.
    items = []
    for sid in scan_ids:
        scan = db.get_scan(sid, user_id)
        if scan is None:
            items.append(({"id": sid, "status": "missing"}, None))
            continue
        if scan["status"] != "done":
            items.append((scan, None))
            continue
        try:
            items.append((scan, db.download_image(sid)))
        except Exception:
            items.append(({**scan, "status": "no_photo"}, None))
    if not any(img is not None for _, img in items):
        raise HTTPException(404, "no completed scans with stored photos")
    pdf = report.build_batch_pdf(items)
    return Response(pdf, media_type="application/pdf", headers={
        "Content-Disposition": f'attachment; filename="inspection_{scan_ids[0][:8]}.pdf"'})


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
