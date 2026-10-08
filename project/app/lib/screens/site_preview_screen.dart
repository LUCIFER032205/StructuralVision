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
import '../theme.dart';
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
  late double _roomSizeM = _fitRoom(BuildingCatalog.roomDefaultM);
  // Where drag / twist left the model, relative to its anchor. A resize or a
  // building switch reloads the node, which would otherwise snap it back.
  vm.Matrix4? _placement;

  List<double> get _roomSteps => BuildingCatalog.roomSteps
      .where((m) => m >= _building.roomMinM)
      .toList();

  double _fitRoom(double m) => m < _building.roomMinM ? _building.roomMinM : m;

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
    // Drag and twist run natively (patched plugin); remember where they end.
    objects.onPanEnd = (_, transform) => _placement = transform;
    objects.onRotationEnd = (_, transform) => _placement = transform;
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
    final local =
        _building.isCustom ? _building.uri : await BuildingCatalog.cached(_building);
    final node = ARNode(
      type: local != null ? NodeType.fileSystemAppFolderGLB : NodeType.webGLB,
      uri: local ?? _building.uri,
      scale: vm.Vector3.all(_building.scaleFor(_mode, roomSizeM: _roomSizeM)),
    );
    if (await _objects?.addNode(node, planeAnchor: _anchor) == true) {
      _node = node;
      final placed = _placement;
      if (placed != null) node.transform = placed; // keeps scale (plugin patch)
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
    if (picked != null) {
      await _reload(() {
        _building = picked;
        _roomSizeM = _fitRoom(_roomSizeM);
      });
    }
  }

  Future<void> _reset() async {
    if (_busy) return;
    if (_node != null) await _objects?.removeNode(_node!);
    if (_anchor != null) await _anchors?.removeAnchor(_anchor!);
    setState(() {
      _node = null;
      _anchor = null;
      _placement = null;
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
        title: const Text('Site preview'),
        actions: [
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
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.black54, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                if (!_planeFound || _busy) ...[
                  const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
                  const SizedBox(width: 12),
                ],
                Expanded(child: Text(hint, style: const TextStyle(color: Colors.white))),
              ]),
            ),
          ),
          // One flat panel docked to the bottom edge (no card-in-card), clear
          // of the system nav bar.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.apartment_rounded,
                            color: AppColors.accent),
                        title: Text(_building.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.titleMd),
                        trailing: const Text('Change',
                            style: TextStyle(color: AppColors.accent)),
                        onTap: _busy ? null : _pickBuilding,
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<PreviewMode>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                                value: PreviewMode.room,
                                label: Text('Miniature'),
                                icon: Icon(Icons.zoom_out_map)),
                            ButtonSegment(
                                value: PreviewMode.site,
                                label: Text('True size'),
                                icon: Icon(Icons.zoom_in_map)),
                          ],
                          selected: {_mode},
                          onSelectionChanged: _busy
                              ? null
                              : (s) => _reload(() => _mode = s.first),
                        ),
                      ),
                      if (_mode == PreviewMode.room)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              tooltip: 'Smaller',
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: _busy || roomStepIndex <= 0
                                  ? null
                                  : () => _reload(
                                      () => _roomSizeM = _roomSteps[roomStepIndex - 1]),
                            ),
                            SizedBox(
                              width: 64,
                              child: Text(_roomLabel,
                                  textAlign: TextAlign.center,
                                  style: AppTextStyles.titleSm),
                            ),
                            IconButton(
                              tooltip: 'Bigger',
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: _busy || roomStepIndex >= _roomSteps.length - 1
                                  ? null
                                  : () => _reload(
                                      () => _roomSizeM = _roomSteps[roomStepIndex + 1]),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
