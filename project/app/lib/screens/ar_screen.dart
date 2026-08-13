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
import '../models.dart';
import 'result_screen.dart' show riskColors;

/// Live AR view: tap a detected plane on the inspected element to pin a
/// 3D marker anchor; risk + component info shown as an overlay badge.
class ArScreen extends StatefulWidget {
  final ScanResult result;

  const ArScreen({super.key, required this.result});

  @override
  State<ArScreen> createState() => _ArScreenState();
}

class _ArScreenState extends State<ArScreen> with SingleTickerProviderStateMixin {
  ARSessionManager? _session;
  ARObjectManager? _objects;
  ARAnchorManager? _anchors;
  bool _placed = false;
  bool _planeFound = false;
  ARNode? _placedNode;
  ARAnchor? _placedAnchor;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;
  bool _vertical = false;
  bool _measuring = false;
  vm.Vector3? _measureStart;
  double? _measureCm;
  double? _widthMm;

  // JBDPA damage class from max residual crack width (Standard for
  // Post-earthquake Damage Level Classification; 13WCEE Nos.124/1179).
  // I <0.2mm, II 0.2-1.0, III 1.0-2.0, IV >2.0. Mirrors backend inference.py.
  static (String, String) _jbdpa(double widthMm) {
    if (widthMm < 0.2) return ('I', 'LOW');
    if (widthMm <= 1.0) return ('II', 'MEDIUM');
    if (widthMm <= 2.0) return ('III', 'HIGH');
    return ('IV', 'HIGH');
  }

  /// Metric width from the two-tap measurement: the measured real length maps
  /// the crack's pixel length to mm, and width follows from the px ratio.
  double? _estimateWidthMm(double measuredCm) {
    final dets = widget.result.detections;
    if (dets.isEmpty) return null;
    final d = dets.reduce((a, b) => a.areaRatio >= b.areaRatio ? a : b);
    if (d.lengthPx <= 0 || d.widthPx <= 0) return null;
    return measuredCm * 10 * (d.widthPx / d.lengthPx);
  }

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.5, end: 1.0).animate(_pulseCtrl);
  }

  // Risk-colored pin GLBs generated into backend/static (see marker_*.glb)
  String get _markerUrl =>
      '${AppConfig.apiBase}/static/marker_${(widget.result.riskLevel ?? 'LOW').toLowerCase()}.glb';

  // Per-scan crack-overlay quad (transparent texture with the crack polygons),
  // built on demand by the backend. Only meaningful when cracks were found.
  bool get _hasCracks => (widget.result.crackCount ?? 0) > 0;
  String get _overlayUrl =>
      '${AppConfig.apiBase}/scan/${widget.result.id}/overlay.glb';

  void _onARViewCreated(
    ARSessionManager session,
    ARObjectManager objects,
    ARAnchorManager anchors,
    ARLocationManager location,
  ) {
    _session = session;
    _objects = objects;
    _anchors = anchors;

    session.onInitialize(
      showPlanes: true,
      // Immediate visual feedback while ARCore is still hunting for planes —
      // on plain surfaces plane detection can take ~1min with nothing on screen.
      showFeaturePoints: true,
      handleTaps: true,
      showWorldOrigin: false,
    );
    objects.onInitialize();
    session.onPlaneOrPointTap = _onTap;
    session.onPlaneDetected = (count) {
      if (!_planeFound && count > 0 && mounted) {
        setState(() => _planeFound = true);
        // Feature-point cloud is only there as pre-plane feedback; leaving it
        // on tanks the frame rate on budget devices (Vivo Y200).
        session.onInitialize(
          showPlanes: true,
          showFeaturePoints: false,
          handleTaps: true,
          showWorldOrigin: false,
        );
      }
    };
  }

  Future<void> _onTap(List<ARHitTestResult> hits) async {
    if (hits.isEmpty) {
      if (_measuring) _toast('No surface there — tap on the detected plane');
      return;
    }
    // Prefer a plane hit, but fall back to any hit — some devices report
    // taps on detected planes as point hits.
    final hit = hits.firstWhere(
      (h) => h.type == ARHitTestResultType.plane,
      orElse: () => hits.first,
    );

    if (_measuring) {
      final p = hit.worldTransform.getTranslation();
      if (_measureStart == null) {
        setState(() => _measureStart = p);
        _toast('Point 1 set — tap the other end of the crack');
      } else {
        setState(() {
          _measureCm = _measureStart!.distanceTo(p) * 100;
          _widthMm = _estimateWidthMm(_measureCm!);
          _measureStart = null;
          _measuring = false;
        });
        _setOverlayHidden(false);
      }
      return;
    }

    if (_placed) return;
    // Claim the slot before any await — rapid taps otherwise all pass the
    // guard and place duplicate overlays.
    setState(() => _placed = true);

    final anchor = ARPlaneAnchor(transformation: hit.worldTransform);
    if (await _anchors?.addAnchor(anchor) != true) {
      setState(() => _placed = false);
      _toast('Could not anchor — try tapping again');
      return;
    }

    final node = ARNode(
      type: NodeType.webGLB,
      // Crack replica quad when cracks were found; risk pin otherwise.
      uri: _hasCracks ? _overlayUrl : _markerUrl,
      // plugin treats scale as scaleToUnits: largest dimension in meters
      // ponytail: fixed 1.0m overlay (0.5 read too small on device) — true
      // physical size needs ARCore Augmented Images, plugin doesn't expose it
      scale: vm.Vector3.all(_hasCracks ? 1.0 : 0.2),
    );
    if (await _objects?.addNode(node, planeAnchor: anchor) == true) {
      _placedNode = node;
      _placedAnchor = anchor;
    } else {
      await _anchors?.removeAnchor(anchor);
      setState(() => _placed = false);
      _toast('Marker failed to load — check backend connection');
    }
  }

  // The placed overlay quad swallows AR taps (node hits don't reach
  // onPlaneOrPointTap), so hide it while measuring and restore after.
  Future<void> _setOverlayHidden(bool hidden) async {
    final node = _placedNode;
    if (node == null) return;
    if (hidden) {
      await _objects?.removeNode(node);
    } else {
      await _objects?.addNode(node,
          planeAnchor: _placedAnchor as ARPlaneAnchor?);
    }
  }

  void _toast(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final risk = widget.result.riskLevel ?? 'LOW';
    final color = riskColors[risk] ?? Colors.grey;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AR inspection'),
        actions: [
          IconButton(
            tooltip: _vertical ? 'Switch to floor planes' : 'Switch to wall planes',
            icon: Icon(_vertical ? Icons.border_horizontal : Icons.border_vertical),
            onPressed: () => setState(() {
              // Recreating ARView drops any placed node — reset placement.
              _vertical = !_vertical;
              _placed = false;
              _planeFound = false;
              _measuring = false;
              _measureStart = null;
              _measureCm = null;
              _widthMm = null;
            }),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: Icon(_measuring ? Icons.close : Icons.straighten),
        label: Text(_measuring ? 'Cancel' : 'Measure'),
        onPressed: () {
          setState(() {
            _measuring = !_measuring;
            _measureStart = null;
            if (_measuring) {
              _measureCm = null;
              _widthMm = null;
            }
          });
          _setOverlayHidden(_measuring);
        },
      ),
      body: Stack(
        children: [
          ARView(
            key: ValueKey(_vertical),
            onARViewCreated: _onARViewCreated,
            // ponytail: vertical mode kept separate from horizontal —
            // horizontalAndVertical SIGSEGVs in libarcore_c.so on Vivo Y200
            // (ARCore 1.54); single-orientation configs to be tested tonight
            planeDetectionConfig: _vertical
                ? PlaneDetectionConfig.vertical
                : PlaneDetectionConfig.horizontal,
          ),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Card(
              color: color.withValues(alpha: 0.9),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$risk RISK — ${widget.result.componentType ?? '?'}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
                    Text(
                      'Cracks: ${widget.result.crackCount ?? 0} · '
                      'Area: ${((widget.result.crackAreaRatio ?? 0) * 100).toStringAsFixed(2)}%',
                      style: const TextStyle(color: Colors.white),
                    ),
                    if (_measuring)
                      Text(
                          _measureStart == null
                              ? 'Measure: tap one end of the crack'
                              : 'Measure: tap the other end',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold))
                    else if (_measureCm != null)
                      Text(
                          'Measured: ${_measureCm!.toStringAsFixed(1)} cm'
                          '${_widthMm != null ? ' · width ≈ ${_widthMm!.toStringAsFixed(1)} mm '
                              '· JBDPA class ${_jbdpa(_widthMm!).$1} (${_jbdpa(_widthMm!).$2})' : ''}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold))
                    else if (!_planeFound)
                      Row(
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white70),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                                _vertical
                                    ? 'Sweep the phone slowly across the wall — textured areas work best'
                                    : 'Sweep the phone slowly across the floor — textured areas work best',
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontStyle: FontStyle.italic)),
                          ),
                        ],
                      )
                    else if (!_placed)
                      Text(
                          _hasCracks
                              ? 'Tap the inspected surface to project the crack pattern'
                              : 'Tap the inspected surface to pin a marker',
                          style: const TextStyle(
                              color: Colors.white70,
                              fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
            ),
          ),
          // Pulsing crosshair shown when plane found but not yet placed
          if (_planeFound && !_placed && !_measuring)
            Center(
              child: AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, __) => Opacity(
                  opacity: _pulseAnim.value,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, color: Colors.white, size: 48,
                          shadows: const [Shadow(blurRadius: 4)]),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _hasCracks ? 'Tap here to project cracks' : 'Tap here to pin marker',
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
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
