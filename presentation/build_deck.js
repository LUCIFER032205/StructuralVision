// StructuralVision AR — principal demo deck
const pptxgen = require("pptxgenjs");
const p = new pptxgen();
p.layout = "LAYOUT_WIDE"; // 13.3 x 7.5

// Palette — matches the app: deep teal primary, mint accent
const TEAL = "00695C";
const DARK = "0B3B36";
const MINT = "50C8B0";
const LIGHT = "F2F7F6";
const ORANGE = "F5A000";
const RED = "E53935";
const GREEN = "43A047";
const GREY = "5B6B68";

const TITLE = { fontFace: "Cambria", bold: true, color: DARK };
const BODY = { fontFace: "Calibri", color: "333333", fontSize: 15 };

const SHOT_W = 2.6, SHOT_H = SHOT_W * 2150 / 1080; // ~5.17 tall
function shot(slide, file, x, y, h) {
  const hh = h || 5.3, ww = hh * 1080 / 2150;
  slide.addImage({ path: `cropped/${file}.png`, x, y, w: ww, h: hh, shadow: { type: "outer", blur: 8, offset: 3, angle: 90, color: "000000", opacity: 0.35 } });
  return ww;
}

// ---------- 1. Title (dark) ----------
let s = p.addSlide();
s.background = { color: DARK };
s.addText("Structural Vision AR", { x: 0.7, y: 2.3, w: 8.6, h: 1.2, fontFace: "Cambria", bold: true, fontSize: 48, color: "FFFFFF" });
s.addText("Intelligent Structural Health Assessment\n& Virtual Building Preview Platform", { x: 0.7, y: 3.5, w: 8.2, h: 1.1, fontFace: "Calibri", fontSize: 20, color: MINT });
s.addText("Kishore  ·  Kiran  ·  Sanjana  ·  Sujan      |      SVIT", { x: 0.7, y: 5.6, w: 8.2, h: 0.5, fontFace: "Calibri", fontSize: 15, color: "BFD8D3" });
shot(s, "06_ar_view", 9.7, 1.1, 5.3);

// ---------- 2. Problem ----------
s = p.addSlide();
s.background = { color: "FFFFFF" };
s.addText("The Problem", { x: 0.7, y: 0.5, w: 8, h: 0.8, ...TITLE, fontSize: 38 });
const probs = [
  ["Manual inspection is slow", "A trained engineer must visit, measure each crack by hand, and write up findings — days per building."],
  ["Expertise is scarce", "Smaller sites and rural buildings rarely get inspected until damage is visible and expensive."],
  ["Subjective severity calls", "Two inspectors can grade the same crack differently; records are photos and notes, not data."],
  ["No early warning", "Cracks that grow between annual inspections go unnoticed until they become structural risks."],
];
probs.forEach(([h, b], i) => {
  const x = 0.7 + (i % 2) * 6.1, y = 1.7 + Math.floor(i / 2) * 2.5;
  s.addShape("roundRect", { x, y, w: 5.7, h: 2.1, rectRadius: 0.08, fill: { color: LIGHT }, line: { type: "none" } });
  s.addShape("ellipse", { x: x + 0.25, y: y + 0.25, w: 0.55, h: 0.55, fill: { color: TEAL }, line: { type: "none" } });
  s.addText(String(i + 1), { x: x + 0.25, y: y + 0.25, w: 0.55, h: 0.55, align: "center", fontFace: "Calibri", bold: true, fontSize: 20, color: "FFFFFF", margin: 0 });
  s.addText(h, { x: x + 1.0, y: y + 0.22, w: 4.5, h: 0.5, fontFace: "Calibri", bold: true, fontSize: 18, color: DARK, margin: 0 });
  s.addText(b, { x: x + 1.0, y: y + 0.75, w: 4.45, h: 1.25, ...BODY, fontSize: 13.5, color: GREY, margin: 0 });
});

// ---------- 3. Solution ----------
s = p.addSlide();
s.background = { color: "FFFFFF" };
s.addText("Our Solution", { x: 0.7, y: 0.5, w: 8, h: 0.8, ...TITLE, fontSize: 38 });
s.addText("A phone app that scans any wall, beam or column and returns a\nstandards-based risk assessment in seconds — visualised in AR.", { x: 0.7, y: 1.4, w: 7.3, h: 1.0, ...BODY, fontSize: 17 });
const feats = [
  ["AI crack detection", "YOLOv8 segmentation traces every crack outline, pixel-accurate."],
  ["Component aware", "A second model recognises column / beam / slab / wall — the same crack matters more on a column."],
  ["Standards-based severity", "Risk graded LOW / MEDIUM / HIGH using JBDPA post-earthquake damage classes."],
  ["AR visualisation", "Detected cracks are re-projected onto the structure, colour-coded by risk, with on-wall width measurement."],
];
feats.forEach(([h, b], i) => {
  const y = 2.6 + i * 1.15;
  s.addShape("ellipse", { x: 0.7, y: y + 0.05, w: 0.45, h: 0.45, fill: { color: MINT }, line: { type: "none" } });
  s.addText("✓", { x: 0.7, y: y + 0.05, w: 0.45, h: 0.45, align: "center", fontSize: 18, bold: true, color: DARK, margin: 0 });
  s.addText(h, { x: 1.35, y, w: 6.0, h: 0.4, fontFace: "Calibri", bold: true, fontSize: 16, color: DARK, margin: 0 });
  s.addText(b, { x: 1.35, y: y + 0.4, w: 6.2, h: 0.6, ...BODY, fontSize: 13, color: GREY, margin: 0 });
});
shot(s, "05_result_medium", 8.6, 1.35, 5.6);

// ---------- 4. How it works (pipeline) ----------
s = p.addSlide();
s.background = { color: "FFFFFF" };
s.addText("How It Works", { x: 0.7, y: 0.5, w: 8, h: 0.8, ...TITLE, fontSize: 38 });
const steps = [
  ["1  Capture", "Photo, gallery image or live video from the phone"],
  ["2  Segment", "YOLOv8-seg outlines every crack (polygon + area + length/width in px)"],
  ["3  Classify", "MobileNetV3 identifies the structural component"],
  ["4  Grade risk", "Area × component weight → LOW / MED / HIGH; AR width measure refines it via JBDPA class"],
  ["5  Visualise", "AR overlay + PDF report, history stored per user"],
];
steps.forEach(([h, b], i) => {
  const x = 0.55 + i * 2.52;
  s.addShape("roundRect", { x, y: 2.2, w: 2.3, h: 2.5, rectRadius: 0.08, fill: { color: i === 3 ? TEAL : LIGHT }, line: { type: "none" } });
  s.addText(h, { x: x + 0.15, y: 2.4, w: 2.0, h: 0.45, fontFace: "Calibri", bold: true, fontSize: 15, color: i === 3 ? "FFFFFF" : DARK, margin: 0 });
  s.addText(b, { x: x + 0.15, y: 2.95, w: 2.0, h: 1.6, ...BODY, fontSize: 11.5, color: i === 3 ? "E0F2EF" : GREY, margin: 0 });
  if (i < 4) s.addText("→", { x: x + 2.28, y: 3.1, w: 0.3, h: 0.5, fontSize: 20, bold: true, color: TEAL, align: "center", margin: 0 });
});
s.addText("On-device app (Flutter)  ·  FastAPI + PyTorch/ONNX backend  ·  works over LAN, USB or secure tunnel — no cloud dependency", { x: 0.7, y: 5.4, w: 12, h: 0.5, ...BODY, fontSize: 14, italic: true, color: TEAL });

// ---------- 5. Live results ----------
s = p.addSlide();
s.background = { color: "FFFFFF" };
s.addText("Live Results — Real Scans", { x: 0.7, y: 0.45, w: 9, h: 0.8, ...TITLE, fontSize: 38 });
let w1 = shot(s, "02_result_high", 0.9, 1.5, 5.2);
let w2 = shot(s, "04_result_high", 5.05, 1.5, 5.2);
let w3 = shot(s, "05_result_medium", 9.2, 1.5, 5.2);
s.addText("LOW — hairline crack, 5.8% area", { x: 0.9, y: 6.8, w: w1 + 0.6, h: 0.4, ...BODY, fontSize: 12, color: GREEN, bold: true, margin: 0 });
s.addText("LOW — fine wall crack, 0.9% area", { x: 5.05, y: 6.8, w: w2 + 0.6, h: 0.4, ...BODY, fontSize: 12, color: GREEN, bold: true, margin: 0 });
s.addText("MEDIUM — open crack, 11.2% area", { x: 9.2, y: 6.8, w: w3 + 0.6, h: 0.4, ...BODY, fontSize: 12, color: ORANGE, bold: true, margin: 0 });

// ---------- 6. Severity grading ----------
s = p.addSlide();
s.background = { color: "FFFFFF" };
s.addText("Standards-Based Severity", { x: 0.7, y: 0.5, w: 10, h: 0.8, ...TITLE, fontSize: 38 });
s.addText("Severity follows the JBDPA post-earthquake damage classification —\ncrack width decides the class, weighted by which component carries load.", { x: 0.7, y: 1.45, w: 7.2, h: 0.95, ...BODY, fontSize: 16 });
const rows = [
  ["Class I", "< 0.2 mm", "LOW", GREEN],
  ["Class II", "0.2 – 1.0 mm", "MEDIUM", ORANGE],
  ["Class III", "1.0 – 2.0 mm", "HIGH", RED],
  ["Class IV", "> 2.0 mm", "HIGH", RED],
];
rows.forEach(([c, wmm, r, col], i) => {
  const y = 2.7 + i * 0.95;
  s.addShape("roundRect", { x: 0.7, y, w: 6.6, h: 0.78, rectRadius: 0.06, fill: { color: LIGHT }, line: { type: "none" } });
  s.addText(c, { x: 1.0, y: y + 0.14, w: 1.6, h: 0.5, fontFace: "Calibri", bold: true, fontSize: 16, color: DARK, margin: 0 });
  s.addText(wmm, { x: 2.8, y: y + 0.14, w: 2.2, h: 0.5, ...BODY, fontSize: 15, margin: 0 });
  s.addShape("roundRect", { x: 5.35, y: y + 0.13, w: 1.55, h: 0.5, rectRadius: 0.1, fill: { color: col }, line: { type: "none" } });
  s.addText(r, { x: 5.35, y: y + 0.13, w: 1.55, h: 0.5, align: "center", fontFace: "Calibri", bold: true, fontSize: 13, color: "FFFFFF", margin: 0 });
});
s.addText("Surface / paint cracks are auto-detected and flagged cosmetic —\nno false alarms from peeling paint.", { x: 0.7, y: 6.55, w: 7.0, h: 0.7, ...BODY, fontSize: 13.5, italic: true, color: GREY });
shot(s, "03_result_2", 8.3, 1.35, 5.7);

// ---------- 7. AR ----------
s = p.addSlide();
s.background = { color: "FFFFFF" };
s.addText("AR Inspection Mode", { x: 0.7, y: 0.5, w: 8, h: 0.8, ...TITLE, fontSize: 38 });
const arf = [
  ["Crack re-projected on site", "The detected crack pattern is anchored onto the real surface — colour-coded by risk (green/orange/red)."],
  ["Two-tap width measurement", "Tap both ends of a crack in AR to get real length; width in mm follows, mapped to its JBDPA class on the spot."],
  ["Tier-2 refinement", "Physical width supersedes the image-area estimate — the metric building standards actually use."],
  ["Instant on-site badge", "Risk, component and crack stats float over the structure while you walk around it."],
];
arf.forEach(([h, b], i) => {
  const y = 1.7 + i * 1.25;
  s.addShape("ellipse", { x: 0.7, y: y + 0.03, w: 0.5, h: 0.5, fill: { color: TEAL }, line: { type: "none" } });
  s.addText(String(i + 1), { x: 0.7, y: y + 0.03, w: 0.5, h: 0.5, align: "center", fontFace: "Calibri", bold: true, fontSize: 16, color: "FFFFFF", margin: 0 });
  s.addText(h, { x: 1.4, y, w: 6.3, h: 0.45, fontFace: "Calibri", bold: true, fontSize: 16, color: DARK, margin: 0 });
  s.addText(b, { x: 1.4, y: y + 0.42, w: 6.5, h: 0.75, ...BODY, fontSize: 13, color: GREY, margin: 0 });
});
shot(s, "06_ar_view", 8.85, 1.15, 5.9);

// ---------- 8. Tech stack ----------
s = p.addSlide();
s.background = { color: "FFFFFF" };
s.addText("Under the Hood", { x: 0.7, y: 0.5, w: 8, h: 0.8, ...TITLE, fontSize: 38 });
const stack = [
  ["Mobile app", "Flutter (Android) — camera, gallery & video scan, AR via ARCore, PDF share"],
  ["Crack model", "YOLOv8 instance segmentation, trained on annotated crack datasets"],
  ["Component model", "MobileNetV3-Small (ONNX) — column / beam / slab / wall / ceiling"],
  ["Backend", "FastAPI + PyTorch/ONNX Runtime — scan pipeline, GLB overlay generator, reports"],
  ["Auth & data", "Supabase (JWT auth) + per-user scan history"],
  ["Deployment", "Runs on a laptop — LAN, USB or Cloudflare tunnel; no GPU or cloud required"],
];
stack.forEach(([h, b], i) => {
  const x = 0.7 + (i % 2) * 6.15, y = 1.7 + Math.floor(i / 2) * 1.75;
  s.addShape("roundRect", { x, y, w: 5.8, h: 1.45, rectRadius: 0.08, fill: { color: LIGHT }, line: { type: "none" } });
  s.addText(h, { x: x + 0.25, y: y + 0.15, w: 5.3, h: 0.4, fontFace: "Calibri", bold: true, fontSize: 15, color: TEAL, margin: 0 });
  s.addText(b, { x: x + 0.25, y: y + 0.6, w: 5.35, h: 0.75, ...BODY, fontSize: 12.5, color: GREY, margin: 0 });
});

// ---------- 9. Closing (dark) ----------
s = p.addSlide();
s.background = { color: DARK };
s.addText("From crack to classified risk\nin under ten seconds.", { x: 0.7, y: 2.0, w: 8.6, h: 1.6, fontFace: "Cambria", bold: true, fontSize: 36, color: "FFFFFF" });
const road = ["Field pilot on campus buildings", "Crack-growth tracking between scans", "iOS support & offline on-device inference"];
s.addText("Next steps", { x: 0.7, y: 4.0, w: 4, h: 0.4, fontFace: "Calibri", bold: true, fontSize: 16, color: MINT });
road.forEach((r, i) => s.addText(r, { x: 0.9, y: 4.5 + i * 0.55, w: 7.5, h: 0.45, fontFace: "Calibri", fontSize: 15, color: "D8ECE8", bullet: { code: "2013" }, margin: 0 }));
shot(s, "01_login", 9.7, 1.1, 5.3);

p.writeFile({ fileName: "StructuralVision_AR_Demo.pptx" }).then(() => console.log("done"));
