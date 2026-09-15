"""Measured-risk chain pinned to the published tables. Run: python test_risk.py
Numbers come from Nakano et al., 13WCEE 2004 Paper 124 (Tables 2-3, R criteria)
and BRE Digest 251 (categories 0-5)."""
from inference import measured_risk, width_from_measurement


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
    width_mm, crack_type = width_from_measurement(20.0, dets)    # 200 mm * 2/400
    assert (round(width_mm, 3), crack_type) == (1.0, "structural")
    assert width_from_measurement(20.0, []) == (None, None)


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok", name)
