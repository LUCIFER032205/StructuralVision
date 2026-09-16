"""Measured-risk chain pinned to the published tables. Run: python test_risk.py
Numbers come from Nakano et al., 13WCEE 2004 Paper 124 (Tables 2-3, R criteria)
and BRE Digest 251 (categories 0-5)."""
from inference import (measured_risk, width_from_measurement,
                       implausible_measurement)


def test_jbdpa_column_brittle_eta():
    r = measured_risk(0.1, "column")        # class I -> eta 0.95 -> R 95 -> Slight
    assert (r["damage_class"], r["residual_capacity_pct"], r["rating"], r["risk_level"]) == ("I", 95.0, "Slight", "LOW")
    r = measured_risk(0.5, "column")        # class II brittle 0.60 -> Moderate
    assert (r["damage_class"], r["residual_capacity_pct"], r["risk_level"]) == ("II", 60.0, "MEDIUM")
    r = measured_risk(1.5, "column")        # class III brittle 0.30 -> Heavy
    assert (r["damage_class"], r["residual_capacity_pct"], r["risk_level"]) == ("III", 30.0, "HIGH")
    r = measured_risk(3.0, "column")        # class IV brittle 0 -> Heavy
    assert (r["damage_class"], r["residual_capacity_pct"], r["risk_level"]) == ("IV", 0.0, "HIGH")


def test_jbdpa_flexural_members_use_ductile_eta():
    assert measured_risk(0.5, "beam")["residual_capacity_pct"] == 75.0    # Moderate
    assert measured_risk(1.5, "slab")["residual_capacity_pct"] == 50.0    # Heavy
    assert measured_risk(3.0, "beam")["residual_capacity_pct"] == 10.0


def test_jbdpa_rc_wall_and_class_edges():
    assert measured_risk(0.5, "rc_wall")["residual_capacity_pct"] == 60.0
    assert measured_risk(0.2, "rc_wall")["damage_class"] == "II"          # "less than 0.2" is class I
    assert measured_risk(1.0, "rc_wall")["damage_class"] == "II"
    assert measured_risk(2.0, "rc_wall")["damage_class"] == "III"
    assert measured_risk(0.5, "rc_wall")["standard"] == "JBDPA"


def test_bre251_masonry_wall():
    cases = [(0.05, "0", "LOW"), (0.8, "1", "LOW"), (4.0, "2", "LOW"),
             (10.0, "3", "MEDIUM"), (20.0, "4", "MEDIUM"), (30.0, "5", "HIGH")]
    for w, cat, risk in cases:
        r = measured_risk(w, "wall")
        assert (r["standard"], r["damage_class"], r["risk_level"]) == ("BRE251", cat, risk), (w, r)
        assert r["residual_capacity_pct"] is None


def test_out_of_scope_is_low():
    assert measured_risk(5.0, "ceiling")["risk_level"] == "LOW"               # non-structural finish
    assert measured_risk(5.0, "column", crack_type="paint")["risk_level"] == "LOW"


def test_width_from_measurement_uses_largest_crack():
    dets = [{"area_ratio": 0.01, "length_px": 100.0, "width_px": 50.0, "crack_type": "paint"},
            {"area_ratio": 0.05, "length_px": 400.0, "width_px": 2.0, "crack_type": "structural"}]
    w = width_from_measurement(20.0, dets)                   # 200 mm * 2/400
    assert (round(w["width_mm"], 3), w["crack_type"]) == (1.0, "structural")
    assert w["uncertain"] is False                           # no photo -> mask only
    assert width_from_measurement(20.0, []) is None


def test_thin_crack_grades_off_the_photo_not_the_bloated_mask():
    """The 2026-09-15 bug: a hairline mask is ~6x wider than the crack, so a
    correct two-tap measurement still graded it HIGH. With the photo in hand
    the trough width drives the grade and the mask becomes the upper bound."""
    import numpy as np
    # 400x400 photo, a 2 px dark vertical line on a light wall
    gray = np.full((400, 400), 200, dtype=np.uint8)
    gray[:, 199:201] = 40
    poly = [[199.0, 10.0], [201.0, 10.0], [201.0, 390.0], [199.0, 390.0]]
    dets = [{"area_ratio": 0.05, "length_px": 380.0, "width_px": 24.0,
             "crack_type": "structural", "polygon": poly}]
    mask_only = width_from_measurement(100.0, dets)
    with_photo = width_from_measurement(100.0, dets, 400, gray)
    # mask says 24/380 of 1000 mm = 63 mm; the actual line is ~2 px = ~5 mm
    assert mask_only["width_mm"] > 50
    assert with_photo["width_mm"] < 15, with_photo
    assert with_photo["uncertain"] is True
    assert with_photo["width_mm_upper"] > with_photo["width_mm"]
    # and that is the difference between a bogus HIGH and a real grade
    assert measured_risk(mask_only["width_mm"], "column")["risk_level"] == "HIGH"
    assert measured_risk(with_photo["width_mm"], "column")["damage_class"] == "IV"


def test_implausible_length_is_rejected_with_a_reason():
    """Taps landing on the floor behind a wall imply an absurd frame size."""
    assert implausible_measurement(400.0, 500.0, 2560) is not None   # ~20 m frame
    assert implausible_measurement(0.5, 1400.0, 2560) is not None    # ~1 cm frame
    assert implausible_measurement(30.0, 1499.0, 2560) is None       # ~50 cm frame, fine


def test_stubby_blobs_are_dropped_but_long_thin_cracks_survive():
    """The perforated-cabinet false alarm (scan cba3bd4f, 2026-09-15) came back
    as round blobs at elongation 1.1-1.9; the thinnest real crack in the same
    session was 25.2. Measured values, not invented ones."""
    from inference import _too_stubby
    for length, width in [(60.0, 50.0), (55.0, 50.0), (95.0, 50.0)]:   # 1.2, 1.1, 1.9
        assert _too_stubby({"length_px": length, "width_px": width}) is True
    for length, width in [(1260.0, 50.0), (1725.0, 50.0)]:             # 25.2, 34.5
        assert _too_stubby({"length_px": length, "width_px": width}) is False
    # a zero-width detection must not divide by zero or be silently dropped
    assert _too_stubby({"length_px": 0.0, "width_px": 0.0}) is False


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok", name)
