"""Skip on an already-measured crack keeps its measurement. Run: python test_crack_status.py"""
import asyncio
import main


class FakeDb:
    def __init__(self, scan): self.scan, self.writes = scan, []
    def get_scan(self, scan_id, user_id): return self.scan
    def update_detection(self, det_id, fields): self.writes.append(fields)
    def update_scan(self, scan_id, fields): self.scan.update(fields)


def run(det_status, new_status):
    m = {"risk_level": "MEDIUM", "width_mm": 0.6, "standard": "JBDPA", "damage_class": "II",
         "rating": "Moderate", "residual_capacity_pct": 60.0}
    det = {"id": "c1", "status": det_status, "measurement": m if det_status == "measured" else None,
           "area_ratio": 0.01}
    fake = FakeDb({"id": "s1", "status": "done", "component_type": "rc_wall", "detections": [det]})
    main.db = fake
    asyncio.run(main.set_crack_status("s1", "c1", main.CrackStatus(status=new_status), "u"))
    return fake


f = run("measured", "skipped")
assert f.writes == [] and f.scan["risk_level"] == "MEDIUM" and f.scan["risk_source"] == "measured"
f = run(None, "skipped")
assert f.writes == [{"status": "skipped", "measurement": None}]
f = run("measured", "not_crack")
assert f.writes == [{"status": "not_crack", "measurement": None}] and f.scan["crack_count"] == 0
print("ok")
