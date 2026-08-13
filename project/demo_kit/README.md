# Demo Kit — curated crack photos

6 images verified against the live pipeline with the **retrained stage2 model**
(2026-07-19), 2 per risk level. For the demo: open each on a second screen/print
and scan it with the phone camera.

| file | risk | area ratio | cracks |
|---|---|---|---|
| high_1.jpg | HIGH | 0.112 | 2 |
| high_2.jpg | HIGH | 0.075 | 3 |
| medium_1.jpg | MEDIUM | 0.025 | 1 |
| medium_2.jpg | MEDIUM | 0.025 | 1 |
| low_1.jpg | LOW | 0.008 | 1 (tiny) |
| low_2.jpg | LOW | 0 | 0 (clean wall) |

> Scanning a photo off a screen adds glare/moire — angle the phone slightly.
> `old_v1/` holds the previous kit (curated for the v1 model — do not use with
> the current model; 3 of 6 mis-scored under it).
> **Re-verify after any future model swap** — rerun a scan of each and check
> the risk badge matches this table.
