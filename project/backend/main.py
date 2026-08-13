"""
main.py — Structural Vision AR backend.

POST /scan          multipart image + JWT  -> {scan_id, status: "pending"}
GET  /scan/{id}     JWT                     -> {status, result?}   (Flutter polls every 2s)

All endpoints require Authorization: Bearer <supabase_jwt>.
"""
from contextlib import asynccontextmanager
from functools import lru_cache
from fastapi import FastAPI, UploadFile, File, Form, BackgroundTasks, HTTPException, Depends
from fastapi.responses import Response
from fastapi.staticfiles import StaticFiles

from inference import run_scan, load_models
from auth import current_user
import db
import overlay
import report


@asynccontextmanager
async def lifespan(app: FastAPI):
    load_models()  # pay the model-load cost once at boot, not on first request
    db.ensure_bucket()
    yield


app = FastAPI(title="Structural Vision AR", lifespan=lifespan)
app.mount("/static", StaticFiles(directory="static"), name="static")


def _process(scan_id: str, image_bytes: bytes, prev_scan_id: str | None = None):
    try:
        result = run_scan(image_bytes)
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
    user_id: str = Depends(current_user),
):
    image_bytes = await image.read()
    scan_id = db.create_scan(user_id)
    bg.add_task(_process, scan_id, image_bytes, prev_scan_id)
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
        scan.get("component_type") or "wall",
        scan.get("component_confidence") or 1.0,
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
