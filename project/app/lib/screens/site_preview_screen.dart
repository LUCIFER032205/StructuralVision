import 'package:ar_flutter_plugin_2/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_2/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin_2/datatypes/node_types.dart';
import 'package:ar_flutter_plugin_2/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_2/models/ar_anchor.dart';
import 'package:ar_flutter_plugin_2/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin_2/models/ar_node.dart';
import 'package:ar_flutter_plugin_2/widgets/ar_view.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import '../building_catalog.dart';
import 'building_select_sheet.dart';

/// AR site preview: place a picked 3D building on any flat surface, in a
/// tabletop-miniature room mode or a true-size site mode. Not tied to any scan.
class SitePreviewScreen extends StatefulWidget {
  final List<BuildingType> buildings;
  const SitePreviewScreen({super.key, required this.buildings});

  @override
  State<SitePreviewScreen> createState() => _SitePreviewScreenState();
}

class _SitePreviewScreenState extends State<SitePreviewScreen> {
  ARSessionManager? _session;
  ARObjectManager? _objects;
  ARAnchorManager? _anchors;
  ARPlaneAnchor? _anchor;
  ARNode? _node;
  bool _planeFound = false;
  bool _busy = false;

  late BuildingType _building = widget.buildings.first;
  PreviewMode _mode = PreviewMode.room; // room first: works anywhere, desk is the demo case
  double _roomSizeM = BuildingCatalog.roomDefaultM;
  static const _roomSteps = [0.2, 0.4, 0.8, 1.5]; // tabletop .. coffee-table size

  String get _roomLabel => _roomSizeM < 1
      ? '${(_roomSizeM * 100).round()} cm'
      : '${_roomSizeM.toStringAsFixed(1)} m';

  void _onARViewCreated(ARSessionManager session, ARObjectManager objects,
      ARAnchorManager anchors, ARLocationManager location) {
    _session = session;
    _objects = objects;
    _anchors = anchors;
    session.onInitialize(
        showPlanes: true, showFeaturePoints: true, handleTaps: true,
        handlePans: true, handleRotation: true, showWorldOrigin: false);
    objects.onInitialize();
    session.onPlaneOrPointTap = _onTap;
    session.onPlaneDetected = (count) {
      if (!_planeFound && count > 0 && mounted) {
        setState(() => _planeFound = true);
        // Feature points tank the frame rate on the Vivo Y200 once planes exist.
        session.onInitialize(
            showPlanes: true, showFeaturePoints: false, handleTaps: true,
            handlePans: true, handleRotation: true, showWorldOrigin: false);
      }
    };
  }

  Future<void> _onTap(List<ARHitTestResult> hits) async {
    if (hits.isEmpty || _anchor != null || _busy) return;
    final hit = hits.firstWhere((h) => h.type == ARHitTestResultType.plane,
        orElse: () => hits.first);
    setState(() => _busy = true); // claim before await: rapid taps place duplicates
    final anchor = ARPlaneAnchor(transformation: hit.worldTransform);
    if (await _anchors?.addAnchor(anchor) != true) {
      _toast('Could not anchor — try tapping again');
    } else {
      _anchor = anchor;
      if (!await _addNode()) {
        await _anchors?.removeAnchor(anchor);
        _anchor = null;
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<bool> _addNode() async {
    final node = ARNode(
      type: _building.isCustom
          ? NodeType.fileSystemAppFolderGLB
          : NodeType.webGLB,
      uri: _building.uri,
      scale: vm.Vector3.all(_building.scaleFor(_mode, roomSizeM: _roomSizeM)),
    );
    if (await _objects?.addNode(node, planeAnchor: _anchor) == true) {
      _node = node;
      return true;
    }
    _toast(_building.isCustom
        ? 'Could not load this model file — try re-importing it'
        : 'Building failed to load — check backend connection');
    return false;
  }

  /// Plugin applies scale only at load, so any change = remove + re-add at the anchor.
  /// Keyed on the anchor, not the node: a failed _addNode() leaves the anchor
  /// set with _node null, and a later switch must still retry the add.
  Future<void> _reload(void Function() change) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      change();
    });
    if (_anchor != null) {
      if (_node != null) {
        await _objects?.removeNode(_node!);
        _node = null;
      }
      await _addNode();
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _pickBuilding() async {
    final picked = await BuildingSelectSheet.show(context,
        buildings: widget.buildings, selectedId: _building.id);
    if (picked != null) await _reload(() => _building = picked);
  }

  Future<void> _reset() async {
    if (_busy) return;
    if (_node != null) await _objects?.removeNode(_node!);
    if (_anchor != null) await _anchors?.removeAnchor(_anchor!);
    setState(() {
      _node = null;
      _anchor = null;
    });
  }

  void _toast(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
    }
  }

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anchored = _anchor != null;
    final placed = _node != null;
    final hint = !_planeFound
        ? 'Sweep the phone slowly across any flat surface — a desk works'
        : !anchored
            ? (_mode == PreviewMode.room
                ? 'Tap a desk or table to place a $_roomLabel model'
                : 'Stand at the edge of the plot and tap the ground where the building goes')
            : !placed
                ? 'Model failed to load — pick another building or tap ⟳ to place again'
                : (_mode == PreviewMode.room
                    ? 'Miniature ($_roomLabel) — walk around it · drag to move, twist with two fingers to rotate'
                    : 'True size: ${_building.footprint.isEmpty ? '' : '${_building.footprint}, '}'
                        '${_building.sizeM.toStringAsFixed(0)} m — '
                        'walk back ~${(_building.sizeM * 1.5).round()} m to see all of it · drag to move, twist with two fingers to rotate');
    final roomStepIndex = _roomSteps.indexOf(_roomSizeM);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Site preview (3D)'),
        actions: [
          ActionChip(
            label: Text(_building.name),
            onPressed: _busy ? null : _pickBuilding,
          ),
          const SizedBox(width: 8),
          if (anchored)
            IconButton(
                tooltip: 'Place again', icon: const Icon(Icons.refresh), onPressed: _reset),
        ],
      ),
      body: Stack(
        children: [
          ARView(
            onARViewCreated: _onARViewCreated,
            // Any horizontal plane: desk, table, floor or ground. Vertical is
            // left off here — a building model belongs on a flat surface anyway.
            planeDetectionConfig: PlaneDetectionConfig.horizontal,
          ),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Card(
              color: Colors.black54,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  if (!_planeFound || _busy) ...[
                    const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70)),
                    const SizedBox(width: 8),
                  ],
                  Expanded(child: Text(hint, style: const TextStyle(color: Colors.white))),
                ]),
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Card(
              color: Colors.black54,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SegmentedButton<PreviewMode>(
                      segments: const [
                        ButtonSegment(
                            value: PreviewMode.room,
                            label: Text('Room (miniature)'),
                            icon: Icon(Icons.zoom_out_map)),
                        ButtonSegment(
                            value: PreviewMode.site,
                            label: Text('Site (true size)'),
                            icon: Icon(Icons.zoom_in_map)),
                      ],
                      selected: {_mode},
                      onSelectionChanged: _busy
                          ? null
                          : (s) => _reload(() => _mode = s.first),
                    ),
                    if (_mode == PreviewMode.room) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.white),
                            onPressed: _busy || roomStepIndex <= 0
                                ? null
                                : () => _reload(
                                    () => _roomSizeM = _roomSteps[roomStepIndex - 1]),
                          ),
                          Text(_roomLabel, style: const TextStyle(color: Colors.white)),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, color: Colors.white),
                            onPressed: _busy || roomStepIndex >= _roomSteps.length - 1
                                ? null
                                : () => _reload(
                                    () => _roomSizeM = _roomSteps[roomStepIndex + 1]),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
