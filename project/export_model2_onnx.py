"""export_model2_onnx.py — export saved best.pt to ONNX + smoke test. No training."""
import torch
import torch.nn as nn
import numpy as np
import onnxruntime as ort
from torchvision import models, datasets, transforms
from pathlib import Path

DATA = Path(r"F:\StructuralVision\datasets\prepared\model2_classifier")
PT   = DATA / "best.pt"
ONNX = DATA / "mobilenet_component.onnx"

ckpt    = torch.load(PT, map_location="cpu")
classes = ckpt["classes"]

model = models.mobilenet_v3_small(weights=None)
model.classifier[3] = nn.Linear(model.classifier[3].in_features, len(classes))
model.load_state_dict(ckpt["model"])
model.eval()

dummy = torch.randn(1, 3, 224, 224)
torch.onnx.export(
    model, dummy, str(ONNX),
    input_names=["input"], output_names=["logits"],
    dynamic_axes={"input": {0: "batch"}, "logits": {0: "batch"}},
    opset_version=13,
)
print(f"ONNX -> {ONNX}  ({ONNX.stat().st_size/1e6:.1f} MB)")

# Smoke test: one real val image, torch vs onnx must agree
val_tf = transforms.Compose([
    transforms.Resize(256), transforms.CenterCrop(224), transforms.ToTensor(),
    transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
])
val_ds = datasets.ImageFolder(DATA / "val", transform=val_tf)
img, label = val_ds[0]
x = img.unsqueeze(0)

with torch.no_grad():
    torch_out = model(x).numpy()
sess = ort.InferenceSession(str(ONNX))
onnx_out = sess.run(None, {"input": x.numpy()})[0]

assert onnx_out.shape == (1, len(classes)), f"bad shape {onnx_out.shape}"
assert np.allclose(torch_out, onnx_out, atol=1e-4), "torch/onnx mismatch"
pred = classes[int(onnx_out.argmax())]
print(f"Smoke test OK. classes={classes}")
print(f"  sample true='{classes[label]}'  onnx_pred='{pred}'  shape={onnx_out.shape}")
