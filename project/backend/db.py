"""
db.py — Supabase persistence for scans + crack_detections.

Uses the service key server-side (bypasses RLS); we set user_id explicitly on
insert so rows still belong to the right user. Client polls through /scan/{id}.
"""
import os
from supabase import create_client, Client

_client: Client | None = None


_BUCKET = "scan-images"


def _conn() -> Client:
    global _client
    if _client is None:
        url = os.environ["SUPABASE_URL"]
        key = os.environ["SUPABASE_SERVICE_KEY"]
        _client = create_client(url, key)
    return _client


def ensure_bucket():
    # ponytail: public bucket, UUID filenames are unguessable; signed URLs if privacy matters
    try:
        _conn().storage.create_bucket(_BUCKET, options={"public": True})
    except Exception:
        pass  # already exists


def upload_image(scan_id: str, image_bytes: bytes) -> str:
    path = f"{scan_id}.jpg"
    _conn().storage.from_(_BUCKET).upload(
        path, image_bytes, {"content-type": "image/jpeg"})
    return _conn().storage.from_(_BUCKET).get_public_url(path)


def download_image(scan_id: str) -> bytes:
    return _conn().storage.from_(_BUCKET).download(f"{scan_id}.jpg")


def create_scan(user_id: str) -> str:
    row = _conn().table("scans").insert({"user_id": user_id, "status": "pending"}).execute()
    return row.data[0]["id"]


def finish_scan(scan_id: str, result: dict, image_url: str | None = None):
    _conn().table("scans").update({
        "status": "done",
        "component_type": result["component_type"],
        "component_confidence": result["component_confidence"],
        "risk_level": result["risk_level"],
        "crack_count": result["crack_count"],
        "crack_area_ratio": result["crack_area_ratio"],
        "image_url": image_url,
    }).eq("id", scan_id).execute()

    detections = [{
        "scan_id": scan_id,
        "bbox": d["bbox"],
        "polygon": d["polygon"],
        "confidence": d["confidence"],
        "area_ratio": d["area_ratio"],
        "crack_type": d.get("crack_type"),
        "length_px": d.get("length_px"),
        "width_px": d.get("width_px"),
        "growth_status": d.get("growth_status"),
        "area_delta": d.get("area_delta"),
    } for d in result["detections"]]
    if detections:
        _conn().table("crack_detections").insert(detections).execute()


def fail_scan(scan_id: str, error: str):
    _conn().table("scans").update({"status": "error", "error": error}).eq("id", scan_id).execute()


def get_scan_unauth(scan_id: str) -> dict | None:
    """For the overlay GLB endpoint — the AR plugin's native loader can't send
    JWT headers. scan_id is an unguessable UUID (same model as the public bucket)."""
    row = _conn().table("scans").select("*").eq("id", scan_id).execute()
    if not row.data:
        return None
    scan = row.data[0]
    dets = _conn().table("crack_detections").select("*").eq("scan_id", scan_id).execute()
    scan["detections"] = dets.data
    return scan


def get_scan(scan_id: str, user_id: str) -> dict | None:
    row = _conn().table("scans").select("*").eq("id", scan_id).eq("user_id", user_id).execute()
    if not row.data:
        return None
    scan = row.data[0]
    if scan["status"] == "done":
        dets = _conn().table("crack_detections").select("*").eq("scan_id", scan_id).execute()
        scan["detections"] = dets.data
    return scan


def list_scans(user_id: str) -> list[dict]:
    return _conn().table("scans").select("*").eq("user_id", user_id) \
        .order("created_at", desc=True).limit(100).execute().data
