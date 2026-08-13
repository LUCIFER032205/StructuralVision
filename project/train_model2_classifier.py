"""
train_model2_classifier.py — MobileNetV3-Small component classifier (CPU)
Classifies structural element: wall / slab / beam / ceiling / column

Handles 80x class imbalance + slow CPU via a WeightedRandomSampler that draws
balanced, fixed-size epochs.
"""

import torch
import torch.nn as nn
from torch.utils.data import DataLoader, WeightedRandomSampler
from torchvision import datasets, transforms, models
from collections import Counter
from pathlib import Path

DATA   = Path(r"F:\StructuralVision\datasets\prepared\model2_classifier")
OUT_PT = DATA / "best.pt"
OUT_ONNX = DATA / "mobilenet_component.onnx"
EPOCHS = 15
EPOCH_SAMPLES = 4000      # balanced draws per epoch (caps CPU cost)
BATCH  = 32
LR     = 1e-3
SEED   = 42

torch.manual_seed(SEED)
device = torch.device("cpu")

IMAGENET_MEAN = [0.485, 0.456, 0.406]
IMAGENET_STD  = [0.229, 0.224, 0.225]

train_tf = transforms.Compose([
    transforms.RandomResizedCrop(224, scale=(0.7, 1.0)),
    transforms.RandomHorizontalFlip(),
    transforms.ToTensor(),
    transforms.Normalize(IMAGENET_MEAN, IMAGENET_STD),
])
val_tf = transforms.Compose([
    transforms.Resize(256),
    transforms.CenterCrop(224),
    transforms.ToTensor(),
    transforms.Normalize(IMAGENET_MEAN, IMAGENET_STD),
])

train_ds = datasets.ImageFolder(DATA / "train", transform=train_tf)
val_ds   = datasets.ImageFolder(DATA / "val",   transform=val_tf)
classes  = train_ds.classes
n_cls    = len(classes)
print("Classes:", classes)

# ── Balanced sampler: weight each sample by 1/class_count ──────────────────────
counts = Counter(lbl for _, lbl in train_ds.samples)
class_w = {c: 1.0 / counts[c] for c in counts}
sample_w = [class_w[lbl] for _, lbl in train_ds.samples]
sampler = WeightedRandomSampler(sample_w, num_samples=EPOCH_SAMPLES, replacement=True)

train_ld = DataLoader(train_ds, batch_size=BATCH, sampler=sampler, num_workers=0)
val_ld   = DataLoader(val_ds,   batch_size=BATCH, shuffle=False,   num_workers=0)

# ── Model: pretrained MobileNetV3-Small, freeze backbone, retrain head ─────────
model = models.mobilenet_v3_small(weights=models.MobileNet_V3_Small_Weights.DEFAULT)
for p in model.features.parameters():
    p.requires_grad = False
model.classifier[3] = nn.Linear(model.classifier[3].in_features, n_cls)
model = model.to(device)

criterion = nn.CrossEntropyLoss()
optimizer = torch.optim.Adam(
    filter(lambda p: p.requires_grad, model.parameters()), lr=LR
)

@torch.no_grad()
def evaluate():
    model.eval()
    correct = total = 0
    per_cls_correct = [0] * n_cls
    per_cls_total   = [0] * n_cls
    for x, y in val_ld:
        x, y = x.to(device), y.to(device)
        pred = model(x).argmax(1)
        correct += (pred == y).sum().item()
        total   += y.size(0)
        for t, p in zip(y.tolist(), pred.tolist()):
            per_cls_total[t]   += 1
            per_cls_correct[t] += (t == p)
    acc = correct / total
    recalls = [per_cls_correct[i] / max(1, per_cls_total[i]) for i in range(n_cls)]
    return acc, recalls, per_cls_correct

# ── Train ──────────────────────────────────────────────────────────────────────
best_acc = 0.0
for epoch in range(1, EPOCHS + 1):
    model.train()
    run_loss = 0.0
    for x, y in train_ld:
        x, y = x.to(device), y.to(device)
        optimizer.zero_grad()
        loss = criterion(model(x), y)
        loss.backward()
        optimizer.step()
        run_loss += loss.item()

    acc, recalls, _ = evaluate()
    rec_str = "  ".join(f"{c}:{r:.2f}" for c, r in zip(classes, recalls))
    print(f"epoch {epoch:2d}  loss={run_loss/len(train_ld):.3f}  val_acc={acc:.3f}  | {rec_str}")

    if acc > best_acc:
        best_acc = acc
        torch.save({"model": model.state_dict(), "classes": classes}, OUT_PT)

print(f"\nBest val_acc: {best_acc:.3f}  ->  {OUT_PT}")

# ── Self-check: rare classes must not be ignored ───────────────────────────────
ckpt = torch.load(OUT_PT, map_location=device)
model.load_state_dict(ckpt["model"])
acc, recalls, per_cls_correct = evaluate()
assert acc > 0.70, f"val acc {acc:.3f} below 0.70 target"
assert all(c > 0 for c in per_cls_correct), \
    f"a class got 0 correct predictions: {dict(zip(classes, per_cls_correct))}"
print("Self-check passed: acc >0.70 and every class predicted correctly at least once.")

# ── Export ONNX for FastAPI ────────────────────────────────────────────────────
model.eval()
dummy = torch.randn(1, 3, 224, 224)
torch.onnx.export(
    model, dummy, str(OUT_ONNX),
    input_names=["input"], output_names=["logits"],
    dynamic_axes={"input": {0: "batch"}, "logits": {0: "batch"}},
    opset_version=13,
)
print(f"ONNX -> {OUT_ONNX}")
