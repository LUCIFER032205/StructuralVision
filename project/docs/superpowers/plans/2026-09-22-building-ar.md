# Building AR Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the one-building site preview into a building AR feature: the user picks a building type (or imports their own model), previews it as a miniature in a room or at true size on an empty plot, and can move, rotate and resize it after placing.

**Architecture:** Building models and their real-world sizes live on the backend (`backend/static/buildings/` + `manifest.json`), so models can be added or swapped without an app release, the same way `building.glb` works today. The app fetches the manifest, shows a picker, and hands the chosen model to the existing `SitePreviewScreen`. That screen swaps its miniature/life-size toggle for Room/Site modes and turns on the AR plugin's built-in drag and rotate. Custom models are copied into the app's documents folder and loaded from there.

**Tech Stack:** Flutter, `ar_flutter_plugin_2` 0.0.3 (ARCore via SceneView), FastAPI static files, Python `trimesh` 4.12 for generating the preset models, `file_picker` + `path_provider` (new, Task 5 only).

**Spec:** No separate spec doc. Requirements come from the 2026-09-22 session and are listed below. The original demo scope is in `project/docs/superpowers/specs/2026-07-12-structural-vision-ar-design.md` §8.

Requirements (from the user, 2026-09-22):
1. Offer several building types to pick from.
2. A miniature mode for previewing the building inside a room when no empty plot is nearby.
3. Better placement controls (move, rotate, resize after placing).
4. A real empty-site mode at true (life) size.
5. More buildings, including the user's own model.

## Global Constraints

- **Plugin scale semantics:** in `ar_flutter_plugin_2` the node's scale X is passed to SceneView as `scaleToUnits` (`ArView.kt:227`). The model is scaled so its **largest dimension equals that many metres**. Every size in this plan is "largest dimension in metres", never a multiplier.
- **Changing scale after load:** the plugin applies scale only when the model loads. To resize, remove the node and add it again (the existing `_toggleScale` pattern). Do not rely on `node.scale = ...` after load.
- **Camera release:** the camera must be released before ARCore opens (`camera_screen.dart:318`, holding it SIGSEGVs `libarcore_c.so`). Every new AR entry point goes through `_openSitePreview`.
- **Performance:** the Vivo drops frames with feature points on. Keep `showFeaturePoints: false` after the first plane (existing behaviour).
- **Models served from backend:** `${AppConfig.apiBase}/static/...`. They must reach the phone over LAN and over the ngrok URL.
- **APK build env:** see `RUN_GUIDE.md`. Set `JAVA_HOME`, `ANDROID_HOME` and `ANDROID_SDK_ROOT` in the same command as `flutter build`.
- **Commits** end with the repo's co-author trailer. Do not commit `TODO.md` or notes files.

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `project/backend/make_buildings.py` | create | Generates the preset GLBs + `manifest.json`; `__main__` self-check |
| `project/backend/static/buildings/*.glb`, `manifest.json` | generated | Served models and their catalogue |
| `project/app/lib/building_catalog.dart` | create | `BuildingType` model, manifest parsing, fetch with offline fallback, scale per mode |
| `project/app/test/building_catalog_test.dart` | create | Unit tests for parsing, fallback and scale |
| `project/app/lib/screens/building_select_sheet.dart` | create | Bottom-sheet picker (same pattern as `component_select_sheet.dart`) |
| `project/app/lib/screens/site_preview_screen.dart` | modify | Takes a `BuildingType`; Room/Site modes; resize steps; drag/rotate; custom import |
| `project/app/lib/screens/camera_screen.dart:318-327` | modify | `_openSitePreview` shows the picker before opening AR |
| `project/app/pubspec.yaml` | modify (Task 5) | `file_picker`, `path_provider` |

---

### Task 1: Preset building models + manifest on the backend

**Files:**
- Create: `project/backend/make_buildings.py`
- Generated: `project/backend/static/buildings/{house,apartment,office}.glb`, `project/backend/static/buildings/manifest.json`
- Copy: `project/backend/static/building.glb` → `project/backend/static/buildings/tower.glb` (keep the original in place; older APKs still load it)

**Interfaces:**
- Produces: `GET /static/buildings/manifest.json` →
  `{"buildings":[{"id":str,"name":str,"file":str,"size_m":float,"storeys":int,"footprint":str}]}`
  where `file` is relative to `/static/buildings/` and `size_m` is the largest real dimension in metres.

Generated models are simple massing models (boxes, floor bands, a roof), which is enough to judge scale on a site. Better-looking Blender or CC0 models can replace any file later without an app change, as long as `size_m` in the manifest is updated.

- [ ] **Step 1: Write the generator with its self-check**

```python
"""Generate preset massing models for the AR site preview.

Run from project/backend:  python make_buildings.py
Writes static/buildings/*.glb and static/buildings/manifest.json.
Swap any .glb for a nicer Blender/CC0 model later; keep size_m in sync.
"""
import json
import shutil
from pathlib import Path

import numpy as np
import trimesh

OUT = Path("static/buildings")
STOREY_M = 3.2
WALL = [236, 226, 208, 255]
BAND = [150, 140, 128, 255]
ROOF = [150, 62, 48, 255]
GLASS = [90, 120, 150, 255]


def _box(w, d, h, z0, color):
    m = trimesh.creation.box(extents=[w, d, h])
    m.apply_translation([0, 0, z0 + h / 2])
    m.visual.face_colors = color
    return m


def building(w, d, storeys, roof):
    """w x d footprint in metres, Z up. Returns a Y-up Trimesh ready for GLB export."""
    h = storeys * STOREY_M
    parts = [_box(w, d, h, 0, WALL)]
    for i in range(1, storeys):                      # floor bands read as storeys
        parts.append(_box(w + 0.1, d + 0.1, 0.25, i * STOREY_M - 0.125, BAND))
    for i in range(storeys):                         # window strip, front face
        z = i * STOREY_M + 1.0
        g = _box(w * 0.8, 0.05, 1.2, z, GLASS)
        g.apply_translation([0, -d / 2 - 0.03, 0])
        parts.append(g)
    if roof == "pitched":
        # Triangular prism as a convex hull: no shapely needed (not installed).
        x, y = w / 2 + 0.3, d / 2 + 0.3
        r = trimesh.Trimesh(vertices=[[sx, sy, sz] for sy in (-y, y)
                                      for sx, sz in ((-x, h), (x, h), (0, h + 2.2))]).convex_hull
        r.visual.face_colors = ROOF
        parts.append(r)
    else:
        parts.append(_box(w + 0.4, d + 0.4, 0.4, h, BAND))  # parapet slab
    mesh = trimesh.util.concatenate(parts)
    # glTF is Y-up: rotate Z-up -> Y-up so the model stands upright in ARCore.
    mesh.apply_transform(trimesh.transformations.rotation_matrix(-np.pi / 2, [1, 0, 0]))
    return mesh


PRESETS = [
    # id, name, w, d, storeys, roof
    ("house", "Independent house (G+1)", 10, 8, 2, "pitched"),
    ("apartment", "Apartment block (G+4)", 18, 12, 5, "flat"),
    ("office", "Office building (G+9)", 20, 20, 10, "flat"),
]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    entries = []
    for pid, name, w, d, storeys, roof in PRESETS:
        mesh = building(w, d, storeys, roof)
        mesh.export(OUT / f"{pid}.glb")
        entries.append({"id": pid, "name": name, "file": f"{pid}.glb",
                        "size_m": round(float(max(mesh.extents)), 1),
                        "storeys": storeys, "footprint": f"{w} x {d} m"})
    shutil.copyfile("static/building.glb", OUT / "tower.glb")
    entries.append({"id": "tower", "name": "Demo tower", "file": "tower.glb",
                    "size_m": 20.0, "storeys": 6, "footprint": "6 x 6 m"})
    (OUT / "manifest.json").write_text(json.dumps({"buildings": entries}, indent=2))
    return entries


if __name__ == "__main__":
    entries = main()
    # Self-check: every file loads back, stands upright (Y is the tallest axis for
    # towers), and size_m matches the exported geometry.
    for e in entries:
        m = trimesh.load(OUT / e["file"], force="mesh")
        assert abs(max(m.extents) - e["size_m"]) < 0.2 or e["id"] == "tower", e
    office = trimesh.load(OUT / "office.glb", force="mesh")
    assert office.extents[1] == max(office.extents), "office should be tallest along Y (up)"
    print("ok:", [(e["id"], e["size_m"]) for e in entries])
```

- [ ] **Step 2: Run it**

Run: `cd project/backend && /c/Python314/python make_buildings.py`
Expected: `ok: [('house', 10.6), ('apartment', 18.4), ('office', 32.4), ('tower', 20.0)]`, and four `.glb` files plus `manifest.json` in `static/buildings/`.

- [ ] **Step 3: Check it is served**

With the backend running: `curl -s http://localhost:8000/static/buildings/manifest.json`
Expected: the JSON above. `curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/static/buildings/house.glb` → `200`.

- [ ] **Step 4: Commit**

```bash
git add project/backend/make_buildings.py project/backend/static/buildings
git commit -m "Building AR: preset massing models and a manifest served from static"
```

---

### Task 2: Building catalogue in the app

**Files:**
- Create: `project/app/lib/building_catalog.dart`
- Test: `project/app/test/building_catalog_test.dart`

**Interfaces:**
- Consumes: the manifest JSON from Task 1.
- Produces:
  ```dart
  enum PreviewMode { room, site }
  class BuildingType {
    final String id, name, footprint;
    final String uri;        // full URL (preset) or documents-folder file name (custom)
    final bool isCustom;
    final double sizeM;      // largest real dimension, metres
    final int storeys;
    double scaleFor(PreviewMode mode, {double roomSizeM = BuildingCatalog.roomDefaultM});
  }
  class BuildingCatalog {
    static const roomDefaultM = 0.4;
    static List<BuildingType> parse(Map<String, dynamic> json, String baseUrl);
    static Future<List<BuildingType>> fetch();   // never throws; falls back to [fallback]
    static BuildingType get fallback;            // the old /static/building.glb tower
  }
  ```

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:structural_vision_ar/building_catalog.dart';

void main() {
  const base = 'http://host:8000';
  final json = {
    'buildings': [
      {'id': 'house', 'name': 'Independent house (G+1)', 'file': 'house.glb',
       'size_m': 10.3, 'storeys': 2, 'footprint': '10 x 8 m'},
      {'id': 'office', 'name': 'Office building (G+9)', 'file': 'office.glb',
       'size_m': 32.0, 'storeys': 10, 'footprint': '20 x 20 m'},
    ]
  };

  test('parse builds full model URLs under /static/buildings/', () {
    final list = BuildingCatalog.parse(json, base);
    expect(list.map((b) => b.id), ['house', 'office']);
    expect(list.first.uri, '$base/static/buildings/house.glb');
    expect(list.first.isCustom, false);
  });

  test('site mode is true size, room mode is tabletop size', () {
    final office = BuildingCatalog.parse(json, base)[1];
    expect(office.scaleFor(PreviewMode.site), 32.0);
    expect(office.scaleFor(PreviewMode.room), BuildingCatalog.roomDefaultM);
    expect(office.scaleFor(PreviewMode.room, roomSizeM: 0.8), 0.8);
  });

  test('parse skips malformed entries instead of failing the whole list', () {
    final list = BuildingCatalog.parse({
      'buildings': [
        {'id': 'bad'},                       // no file / size
        json['buildings']![0],
      ]
    }, base);
    expect(list.single.id, 'house');
  });

  test('fallback is the legacy tower so the screen always has something', () {
    expect(BuildingCatalog.fallback.uri, endsWith('/static/building.glb'));
    expect(BuildingCatalog.fallback.sizeM, 20.0);
  });
}
```

- [ ] **Step 2: Run to confirm it fails**

Run: `cd project/app && F:/flutter/bin/flutter.bat test test/building_catalog_test.dart`
Expected: compile error, `building_catalog.dart` not found.

- [ ] **Step 3: Implement**

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';

enum PreviewMode { room, site }

class BuildingType {
  final String id, name, footprint;
  final String uri;
  final bool isCustom;
  final double sizeM;
  final int storeys;

  const BuildingType({
    required this.id,
    required this.name,
    required this.uri,
    required this.sizeM,
    this.footprint = '',
    this.storeys = 0,
    this.isCustom = false,
  });

  /// Plugin scale = largest model dimension in metres (see site_preview_screen).
  double scaleFor(PreviewMode mode,
          {double roomSizeM = BuildingCatalog.roomDefaultM}) =>
      mode == PreviewMode.site ? sizeM : roomSizeM;
}

class BuildingCatalog {
  static const roomDefaultM = 0.4;

  static BuildingType get fallback => BuildingType(
        id: 'tower',
        name: 'Demo tower',
        uri: '${AppConfig.apiBase}/static/building.glb',
        sizeM: 20.0,
        storeys: 6,
        footprint: '6 x 6 m',
      );

  static List<BuildingType> parse(Map<String, dynamic> json, String baseUrl) {
    final out = <BuildingType>[];
    for (final raw in (json['buildings'] as List? ?? const [])) {
      final e = raw as Map<String, dynamic>;
      final file = e['file'], size = e['size_m'];
      if (file is! String || size is! num) continue; // one bad row can't blank the picker
      out.add(BuildingType(
        id: e['id'] as String? ?? file,
        name: e['name'] as String? ?? file,
        uri: '$baseUrl/static/buildings/$file',
        sizeM: size.toDouble(),
        storeys: (e['storeys'] as num?)?.toInt() ?? 0,
        footprint: e['footprint'] as String? ?? '',
      ));
    }
    return out;
  }

  /// Never throws: an unreachable backend still gets the legacy tower.
  static Future<List<BuildingType>> fetch() async {
    final base = AppConfig.apiBase;
    try {
      final r = await http
          .get(Uri.parse('$base/static/buildings/manifest.json'),
              headers: {'ngrok-skip-browser-warning': '1'})
          .timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final list = parse(jsonDecode(r.body) as Map<String, dynamic>, base);
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}
    return [fallback];
  }
}
```

- [ ] **Step 4: Run tests**

Run: `F:/flutter/bin/flutter.bat test test/building_catalog_test.dart`
Expected: all 4 pass.

- [ ] **Step 5: Commit**

```bash
git add project/app/lib/building_catalog.dart project/app/test/building_catalog_test.dart
git commit -m "Building AR: catalogue of building types fetched from the backend"
```

---

### Task 3: Building picker + Room/Site modes + resize

This task makes requirements 1, 2 and 4 usable on a phone.

**Files:**
- Create: `project/app/lib/screens/building_select_sheet.dart`
- Modify: `project/app/lib/screens/site_preview_screen.dart` (whole file; replaces the `_lifeSize` toggle)
- Modify: `project/app/lib/screens/camera_screen.dart:318-327` (`_openSitePreview`)

**Interfaces:**
- Consumes: `BuildingType`, `BuildingCatalog.fetch()`, `PreviewMode`, `scaleFor` (Task 2).
- Produces: `SitePreviewScreen({required List<BuildingType> buildings})`, plus
  `static Future<BuildingType?> BuildingSelectSheet.show(BuildContext, {required List<BuildingType> buildings, String? selectedId})`.

- [ ] **Step 1: Picker sheet**

Follow `component_select_sheet.dart`: full-width rows, a tick on the current pick, icon, name, and a one-line hint `"${b.footprint} · ${b.storeys} storeys · ${b.sizeM.toStringAsFixed(0)} m"`. Custom models show `"Your model · ${sizeM} m"`. The sheet returns the tapped `BuildingType`, or null if dismissed.

- [ ] **Step 2: Screen state changes in `site_preview_screen.dart`**

Replace `bool _lifeSize` with:

```dart
late BuildingType _building = widget.buildings.first;
PreviewMode _mode = PreviewMode.room;          // room first: works anywhere, desk is the demo case
double _roomSizeM = BuildingCatalog.roomDefaultM;
static const _roomSteps = [0.2, 0.4, 0.8, 1.5]; // tabletop .. coffee-table size
```

`_addNode()` uses `uri: _building.uri`, `type: _building.isCustom ? NodeType.fileSystemAppFolderGLB : NodeType.webGLB`, and `scale: vm.Vector3.all(_building.scaleFor(_mode, roomSizeM: _roomSizeM))`.

Add one helper that every "change what is shown" action goes through. It is the existing `_toggleScale` body, generalised:

```dart
/// Plugin applies scale only at load, so any change = remove + re-add at the anchor.
Future<void> _reload(void Function() change) async {
  if (_busy) return;
  setState(() { _busy = true; change(); });
  if (_node != null) {
    await _objects?.removeNode(_node!);
    _node = null;
    await _addNode();
  }
  if (mounted) setState(() => _busy = false);
}
```

- [ ] **Step 3: Controls**

- App bar action: building name chip → `BuildingSelectSheet.show` → `_reload(() => _building = picked)`.
- Replace the FAB with a bottom `SegmentedButton<PreviewMode>`: **Room (miniature)** / **Site (true size)** → `_reload(() => _mode = m)`.
- In Room mode only, show `−` / `+` buttons that step through `_roomSteps` with `_reload(() => _roomSizeM = next)`. Show the current size, e.g. "40 cm".
- Hints:
  - room, not placed: `'Tap a desk or table to place a ${_roomLabel} model'`
  - site, not placed: `'Stand at the edge of the plot and tap the ground where the building goes'`
  - site, placed: `'True size: ${_building.footprint}, ${_building.sizeM.toStringAsFixed(0)} m — walk back ~${(_building.sizeM * 1.5).round()} m to see all of it'`

- [ ] **Step 4: Entry point**

In `camera_screen.dart` `_openSitePreview`, after releasing the camera:

```dart
final buildings = await BuildingCatalog.fetch();
if (!mounted) return;
await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => SitePreviewScreen(buildings: buildings)));
```

(Keep the camera release first and the `_init()` afterwards. See Global Constraints.)

- [ ] **Step 5: Analyze + existing tests**

Run: `F:/flutter/bin/flutter.bat analyze lib && F:/flutter/bin/flutter.bat test`
Expected: no issues; all tests pass.

- [ ] **Step 6: Commit**

```bash
git add project/app/lib/screens/building_select_sheet.dart project/app/lib/screens/site_preview_screen.dart project/app/lib/screens/camera_screen.dart
git commit -m "Building AR: pick a building type, room miniature vs true-size site mode"
```

---

### Task 4: Move and rotate after placing

**Files:**
- Modify: `project/app/lib/screens/site_preview_screen.dart` (`_onARViewCreated`)

The plugin already implements drag and twist natively (`ArView.kt`, `ModelNode.onMove` / `onRotate`) behind two flags that are off by default (`ar_session_manager.dart:194-195`).

- [ ] **Step 1: Enable them in both `session.onInitialize` calls**

```dart
session.onInitialize(
    showPlanes: true, showFeaturePoints: true, handleTaps: true,
    handlePans: true, handleRotation: true, showWorldOrigin: false);
```

(and the same flags in the second call that turns feature points off).

- [ ] **Step 2: Keep the move across a reload**

`_reload` re-adds the node at the anchor, so a drag or twist would be lost on every resize or mode switch. Record the last transform and re-apply it:

```dart
Matrix4? _userTransform;   // last drag/rotate result, relative to the anchor
...
objects.onPanEnd = (name, transform) => _userTransform = transform;
objects.onRotationEnd = (name, transform) => _userTransform = transform;
```

In `_addNode()`, when `_userTransform != null`, build the node with `transformation: _userTransform` and then set `node.scale = vm.Vector3.all(scale)` **before** `addNode`, so scale is still applied at load. `_reset()` clears `_userTransform`.

- [ ] **Step 3: Hint for the new gestures**

Once placed, append to the hint: `' · drag to move, twist with two fingers to rotate'`.

- [ ] **Step 4: Analyze, then commit**

Run: `F:/flutter/bin/flutter.bat analyze lib/screens/site_preview_screen.dart` → no issues.

```bash
git add project/app/lib/screens/site_preview_screen.dart
git commit -m "Building AR: drag to move and twist to rotate a placed building"
```

---

### Task 5: Import your own building model

This is requirement 5 (custom models). It is the only task that adds dependencies.

**Files:**
- Modify: `project/app/pubspec.yaml` (add `file_picker`, `path_provider`)
- Modify: `project/app/lib/screens/building_select_sheet.dart` (an "Import .glb…" row)
- Create: nothing else. Import logic lives in the sheet, the one place that uses it.

**Interfaces:**
- Produces: a `BuildingType(isCustom: true, uri: '<fileName>.glb', sizeM: <user value>)`. `uri` is a file name **relative to the app documents folder**, which is what `NodeType.fileSystemAppFolderGLB` expects.

- [ ] **Step 1: Dependencies**

Run: `F:/flutter/bin/flutter.bat pub add file_picker path_provider`

- [ ] **Step 2: Import row**

A last row in the sheet, "Import your own model (.glb)", that:
1. Calls `FilePicker.platform.pickFiles(type: FileType.any)`. Android's picker can't filter by `.glb` MIME type, so check the extension afterwards and show "Only .glb files are supported" otherwise.
2. Copies the file to `(await getApplicationDocumentsDirectory()).path/custom_<millis>.glb`.
3. Asks one question in a dialog: "How big is the real building? (largest side, metres)", with a numeric field defaulting to `10`, accepting 1–300.
4. Returns `BuildingType(id: 'custom', name: <original file name>, uri: 'custom_<millis>.glb', sizeM: value, isCustom: true)`.

Custom models are not saved between sessions (YAGNI). Add persistence only if the user asks.

- [ ] **Step 3: Analyze + commit**

```bash
git add project/app/pubspec.yaml project/app/pubspec.lock project/app/lib/screens/building_select_sheet.dart
git commit -m "Building AR: import your own .glb building model"
```

---

### Task 6: Build + device test

**Files:** none (build and test only).

- [ ] **Step 1: Build and publish the APK**

```powershell
$env:JAVA_HOME='F:\StructuralVision\tools\jdk-17'; $env:ANDROID_HOME='F:\android-sdk'; $env:ANDROID_SDK_ROOT='F:\android-sdk'
cd F:\StructuralVision\project\app
F:\flutter\bin\flutter.bat build apk --release --dart-define-from-file=dart_defines.env
Copy-Item build\app\outputs\flutter-apk\app-release.apk ..\backend\static\structural_vision_ar.apk -Force
```

- [ ] **Step 2: Device checklist (vivo)**

- [ ] Picker lists house / apartment / office / demo tower; with the backend stopped it still opens with the demo tower
- [ ] Room mode on a desk: building appears ~40 cm; − / + steps 20 cm → 1.5 m
- [ ] Switch to Site mode on the same anchor: building jumps to true size
- [ ] Site mode outdoors on real ground: house reads as ~2 storeys next to a real person
- [ ] Drag moves it along the surface; two-finger twist rotates it; both survive a resize
- [ ] Switch building in the picker while placed: new model at the same spot
- [ ] Import a `.glb` from Downloads, enter 15 m, and it places correctly; a `.jpg` is rejected with a message
- [ ] Frame rate stays usable with the office model at true size (the largest model)

## Out of scope (ask before adding)

- Pinch-to-scale in Site mode: true size should stay true.
- Saving imported models or placements between sessions.
- GPS / geospatial anchoring to a surveyed plot: needs the ARCore Geospatial API, which this plugin does not expose.
- Crack pins on the building model: the user didn't pick this; it is a separate plan.
