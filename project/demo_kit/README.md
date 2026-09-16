# Demo Kit — curated crack photos

6 images, re-verified 2026-09-16 against the **v4 model** (conf 0.4, iou 0.45,
minimum elongation 4.0), scanned as component **column**. The elongation filter
added 2026-09-16 leaves every row below unchanged. Labels are the intended severity; `v4 risk` is
what the pipeline returns now.

| file | label | v4 risk | area ratio | cracks |
|---|---|---|---|---|
| high_1.jpg | HIGH | HIGH | 0.056 | 1 |
| high_2.jpg | HIGH | MEDIUM | 0.043 | 2 (1 tagged paint) |
| medium_1.jpg | MEDIUM | MEDIUM | 0.023 | 1 |
| medium_2.jpg | MEDIUM | LOW | 0.026 | 1 (tagged paint) |
| low_1.jpg | LOW | LOW | 0.009 | 1 (tiny) |
| low_2.jpg | LOW | LOW | 0 | 0 (clean wall) |

For the demo use high_1 / medium_1 / low_1 — those grade exactly as labeled.

> Scanning a photo off a screen adds glare/moire — angle the phone slightly.
> `old_v1/` holds the previous kit (curated for the v1 model — do not use with
> the current model; 3 of 6 mis-scored under it).
> **Re-verify after any future model swap** — rerun a scan of each and check
> the risk badge matches this table. `python project/backend/inference.py`
> prints the whole table in one go.
>
> `missed.jpeg` (added 2026-09-16) is NOT part of the graded kit — it is the
> façade photograph the model misses entirely at conf 0.4, kept as the only
> local reproduction of that failure. See §5b of
> `docs/model_evolution_report.md` before trying to "fix" it.
