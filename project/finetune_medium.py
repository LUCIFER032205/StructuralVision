# v4: fine-tune the MEDIUM model (v2 crack_seg.pt) on the 9,816-image merged dataset.
#
# Why medium: on CPU the large model needs ~4.3s/image against a 3s budget, and at
# epoch40 it still lost to v2 on masks (0.618 vs 0.675). Medium runs at ~1.0s.
#
# Target: beat v2's mask mAP50 of 0.675 on the 200-image crack.yolov8 valid set.
#
# Guards learned the hard way (two NaN collapses):
#   amp=False          fp16 removed as a variable
#   warmup_epochs=3    warmup_epochs=0 compresses the 0.1 bias-LR ramp into 100 iters
#   save_period=1      every epoch kept; best.pt is box-only fitness in 8.4.123
#   stop_on_nan        halts within one epoch instead of burning hours
#
# Copy each CELL into a Kaggle notebook cell, in order. GPU T4 x2.
# Attach as Kaggle Datasets: the merged dataset, and crack_seg.pt (found automatically).

# ============================================================
# CELL 1: Setup
# ============================================================
import os
os.environ['WANDB_DISABLED'] = 'true'
!pip install -q ultralytics==8.4.123
!pip uninstall -y -q wandb

import torch, shutil, pandas as pd
from pathlib import Path
from ultralytics import YOLO

print(f"CUDA: {torch.cuda.is_available()}  GPU: {torch.cuda.get_device_name(0)}")


# ============================================================
# CELL 2: Dataset + the 200-image decision set
# ============================================================
roots = [d.parent.parent for d in Path('/kaggle/input').rglob('valid/images')
         if (d.parent.parent / 'train/images').exists()]
if not roots:
    print("inputs attached:", [str(x) for x in Path('/kaggle/input').glob('*')])
    raise SystemExit("no train+valid split found under /kaggle/input")
src = roots[0]
print("dataset root:", src)

dst = Path('/kaggle/working/fixed_dataset')
assert src != dst, "src and dst must differ"
n = lambda root, s: len(list((root/s/'images').glob('*'))) if (root/s/'images').exists() else 0
if dst.exists() and (n(dst, 'train'), n(dst, 'valid')) != (n(src, 'train'), n(src, 'valid')):
    print("stale/incomplete copy - removing")   # an interrupted copytree leaves a partial train/ + truncated files
    shutil.rmtree(dst)
if not dst.exists():
    shutil.copytree(src, dst)
print("train:", n(dst, 'train'), "valid:", n(dst, 'valid'))   # expect 9816 / 1239
assert (n(dst, 'train'), n(dst, 'valid')) == (9816, 1239), "wrong or partial dataset - do not train"

Path('/kaggle/working/data.yaml').write_text(
    f"path: {dst}\ntrain: train/images\nval: valid/images\nnc: 1\nnames:\n  0: crack\n")

# The decision set: the same 200 images where v2 scores 0.675 mask mAP50.
ev = Path('/kaggle/working/eval200')
shutil.rmtree(ev, ignore_errors=True)
(ev/'images').mkdir(parents=True); (ev/'labels').mkdir(parents=True)

src_imgs = sorted((dst/'valid/images').glob('crack_yolov8_valid_*'))
if not src_imgs:
    seen = sorted({f.name.split('_valid_')[0] for f in (dst/'valid/images').iterdir()})
    print("prefixes actually present:", seen)
    raise SystemExit("no crack_yolov8_valid_* images found")

for img in src_imgs:
    shutil.copy2(img, ev/'images'/img.name)
    lbl = dst/'valid/labels'/(img.stem + '.txt')
    if lbl.exists():
        shutil.copy2(lbl, ev/'labels'/lbl.name)

n_img = len(list((ev/'images').glob('*')))
print(f"eval200: {n_img} images / {len(list((ev/'labels').glob('*.txt')))} labels")
assert n_img == 200, f"expected 200, got {n_img}"

Path('/kaggle/working/eval200.yaml').write_text(
    f"path: {ev}\ntrain: images\nval: images\nnc: 1\nnames:\n  0: crack\n")


# ============================================================
# CELL 3: Find v2 weights and reproduce the 0.675 baseline
# ============================================================
found = sorted(Path('/kaggle/input').rglob('crack_seg.pt'))
if not found:
    print("inputs attached:", [str(x) for x in Path('/kaggle/input').glob('*')])
    raise SystemExit("crack_seg.pt not found - upload project/models/crack_seg.pt as a Dataset")
ckpt = Path('/kaggle/working/crack_seg.pt')
if not ckpt.exists():
    shutil.copy2(found[0], ckpt)
print("v2 weights:", found[0], f"({ckpt.stat().st_size/1e6:.0f} MB)")

base = YOLO(str(ckpt)).val(data='/kaggle/working/eval200.yaml', imgsz=1024, batch=8)
BASE = base.seg.map50
print(f"\nv2 baseline on the 200: mask mAP50 {BASE:.3f}  (local CPU run said 0.675)")
print("If this is far from 0.675, STOP - wrong weights or wrong eval set.")


# ============================================================
# CELL 4: Train with every guard on
# ============================================================
model = YOLO(str(ckpt))

def stop_on_nan(trainer):
    t = trainer.tloss                       # dict of losses in 8.4.123, tensor in others
    vals = list(t.values()) if isinstance(t, dict) else ([] if t is None else [t])
    if any(torch.is_tensor(v) and torch.isnan(v).any() for v in vals):
        print("!! NaN loss - stopping now, earlier epochs are safe")
        trainer.stop = True

model.add_callback("on_train_epoch_end", stop_on_nan)

model.train(
    data='/kaggle/working/data.yaml',
    epochs=30, imgsz=1024, batch=4, device=0, optimizer='AdamW',  # batch=8 OOMs on T4 with amp=False
    time=10.5,                              # hours; ultralytics re-fits epochs + LR schedule to this (12h Kaggle cap)
    lr0=0.001, lrf=0.01, warmup_epochs=3,   # NOT 0: that compressed the bias-LR ramp
    amp=False,                              # fp16 out of the picture
    mosaic=1.0, copy_paste=0.0, close_mosaic=3,  # time= cuts this to ~13 epochs; 10 would leave mosaic almost off
    save_period=1,                          # best.pt uses box-only fitness - do not trust it
    project='runs', name='v4_medium', exist_ok=True,
    plots=True, val=True,
)
print("training returned")   # keeps Jupyter from dumping the whole metrics object


# ============================================================
# CELL 5: Pick the best MASK epoch and score it on the 200
# ============================================================
run = sorted(Path('/kaggle/working').rglob('v4_medium/results.csv'))[-1].parent
df = pd.read_csv(run / 'results.csv')
df.columns = df.columns.str.strip()
print(df[['epoch', 'train/seg_loss', 'metrics/mAP50(M)', 'metrics/recall(M)']].to_string(index=False))

best_epoch = int(df.loc[df['metrics/mAP50(M)'].idxmax(), 'epoch'])
cand = run / 'weights' / f'epoch{best_epoch}.pt'
if not cand.exists():
    cand = run / 'weights' / 'last.pt'
print("best mask epoch:", best_epoch, "->", cand)

r = YOLO(str(cand)).val(data='/kaggle/working/eval200.yaml', imgsz=1024, batch=8)
print()
print("================ VERDICT ================")
print(f"v2 (serving now) : mask mAP50 {BASE:.3f}")
print(f"this run         : mask mAP50 {r.seg.map50:.3f}   recall {r.seg.mr:.3f}")
print("=========================================")
print("Higher? Download that epoch file, time one CPU predict, then swap crack_seg.pt.")
print("Lower or equal? The extra 6k images do not help this domain - stop here.")
