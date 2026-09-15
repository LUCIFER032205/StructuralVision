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

import '../config.dart';

// Plugin scale = largest model dimension in metres (building.glb is a tower).
const _miniatureM = 0.4; // tabletop model
const _lifeSizeM = 20.0; // ~6-storey block, 6 m footprint

/// AR site preview: place a preset 3D building on a floor/ground plane,
/// toggle tabletop miniature vs life-size. Not tied to any scan.
class SitePreviewScreen extends StatefulWidget {
  const SitePreviewScreen({super.key});

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
  bool _lifeSize = false;

  // Served from backend/static, so the model can be swapped without an app update.
  String get _modelUrl => '${AppConfig.apiBase}/static/building.glb';

  void _onARViewCreated(ARSessionManager session, ARObjectManager objects,
      ARAnchorManager anchors, ARLocationManager location) {
    _session = session;
    _objects = objects;
    _anchors = anchors;
    session.onInitialize(
        showPlanes: true, showFeaturePoints: true, handleTaps: true, showWorldOrigin: false);
    objects.onInitialize();
    session.onPlaneOrPointTap = _onTap;
    session.onPlaneDetected = (count) {
      if (!_planeFound && count > 0 && mounted) {
        setState(() => _planeFound = true);
        // Feature points tank the frame rate on the Vivo Y200 once planes exist.
        session.onInitialize(
            showPlanes: true, showFeaturePoints: false, handleTaps: true, showWorldOrigin: false);
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
      type: NodeType.webGLB,
      uri: _modelUrl,
      scale: vm.Vector3.all(_lifeSize ? _lifeSizeM : _miniatureM),
    );
    if (await _objects?.addNode(node, planeAnchor: _anchor) == true) {
      _node = node;
      return true;
    }
    _toast('Building failed to load — check backend connection');
    return false;
  }

  // Re-add at the new size; the plugin applies scale when the model loads.
  Future<void> _toggleScale() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _lifeSize = !_lifeSize;
    });
    if (_node != null) {
      await _objects?.removeNode(_node!);
      _node = null;
      await _addNode();
    }
    if (mounted) setState(() => _busy = false);
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
    final placed = _anchor != null;
    final hint = !_planeFound
        ? 'Sweep the phone slowly across the floor or ground'
        : !placed
            ? 'Tap the floor to place the building'
            : _lifeSize
                ? 'Life-size (20 m) — step back or walk around it'
                : 'Miniature (40 cm) — walk around it';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Site preview (3D)'),
        actions: [
          if (placed)
            IconButton(
                tooltip: 'Place again', icon: const Icon(Icons.refresh), onPressed: _reset),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: Icon(_lifeSize ? Icons.zoom_in_map : Icons.zoom_out_map),
        label: Text(_lifeSize ? 'Miniature' : 'Life-size'),
        onPressed: _busy ? null : _toggleScale,
      ),
      body: Stack(
        children: [
          ARView(
            onARViewCreated: _onARViewCreated,
            // Floor/ground only: horizontalAndVertical SIGSEGVs on the Vivo Y200.
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
        ],
      ),
    );
  }
}
