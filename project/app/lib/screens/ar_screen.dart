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
import '../scan_api.dart';
import 'result_screen.dart' show riskColors;

/// Live AR view: tap a detected plane on the inspected element to pin a
/// 3D marker anchor; risk + component info shown as an overlay badge.
class ArScreen extends StatefulWidget {
  final ScanResult result;
  final bool startMeasuring; // opened from "Measure crack for a grade"

  const ArScreen({super.key, required this.result, this.startMeasuring = false});

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
  late bool _measuring = widget.startMeasuring;
  vm.Vector3? _measureStart;
  double? _measureCm;
  bool _grading = false;
  // Starts as the scan's preliminary result; replaced by the backend's
  // standards-graded result (JBDPA / BRE 251) after a measurement. Width
  // conversion and grading live only in backend inference.py.
  late ScanResult _result = widget.result;

  Future<void> _submitMeasurement(double lengthCm) async {
    setState(() => _grading = true);
    try {
      final updated = await scanApi.submitMeasurement(_result.id, lengthCm);
      if (mounted) setState(() => _result = updated);
    } on MeasurementRejected catch (e) {
      // The backend checks the implied frame size; taps that land on the floor
      // behind a wall come back here instead of producing a bogus grade.
      if (mounted) {
        setState(() => _measureCm = null);
        _toast(e.message, seconds: 5);
      }
    } catch (e) {
      _toast('Could not grade measurement: $e');
    } finally {
      if (mounted) setState(() => _grading = false);
    }
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
      '${AppConfig.apiBase}/static/marker_${(_result.riskLevel ?? 'LOW').toLowerCase()}.glb';

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
          _measureStart = null;
          _measuring = false;
        });
        _setOverlayHidden(false);
        _submitMeasurement(_measureCm!);
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
  // onPlaneOrPointTap), so it has to come off while measuring. Removing it
  // left the user with no guide at all, which is half of why measurements
  // landed on the wrong surface — the on-screen measure guide below replaces
  // it for the duration.
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

  void _toast(String msg, {int seconds = 2}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: Duration(seconds: seconds)));
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
    final risk = _result.riskLevel ?? 'LOW';
    final color = riskColors[risk] ?? Colors.grey;
    // Hand the (possibly re-graded) scan back so the result screen updates.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_result);
      },
      child: Scaffold(
      // The wall-plane toggle is gone: PlaneDetectionConfig.vertical (and
      // horizontalAndVertical) SIGSEGV in libarcore_c.so on the Vivo Y200,
      // confirmed 2026-09-15. AR measuring is floor/slab only; wall, column
      // and beam cracks are measured by typing a ruler reading on the result
      // screen, which posts to the same endpoint.
      appBar: AppBar(title: const Text('AR inspection')),
      floatingActionButton: FloatingActionButton.extended(
        icon: Icon(_measuring ? Icons.close : Icons.straighten),
        label: Text(_measuring ? 'Cancel' : 'Measure'),
        onPressed: () {
          setState(() {
            _measuring = !_measuring;
            _measureStart = null;
            if (_measuring) {
              _measureCm = null;
            }
          });
          _setOverlayHidden(_measuring);
        },
      ),
      body: Stack(
        children: [
          ARView(
            onARViewCreated: _onARViewCreated,
            planeDetectionConfig: PlaneDetectionConfig.horizontal,
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
                      '$risk RISK${_result.isMeasured ? '' : ' (preliminary)'} — ${_result.componentType ?? '?'}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
                    Text(
                      'Cracks: ${_result.crackCount ?? 0} · '
                      'Area: ${((_result.crackAreaRatio ?? 0) * 100).toStringAsFixed(2)}%',
                      style: const TextStyle(color: Colors.white),
                    ),
                    if (_measuring)
                      Text(
                          _measureStart == null
                              ? 'Measure: tap one end of the crack on the floor plane'
                              : 'Measure: tap the other end',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold))
                    else if (_measureCm != null)
                      Text(
                          'Measured: ${_measureCm!.toStringAsFixed(1)} cm'
                          '${_grading ? ' · grading…' : _result.isMeasured ? ' · width ≈ ${_result.widthSummary} · ${_result.gradeSummary}' : ''}',
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
                                'Sweep the phone slowly across the floor — textured areas work best',
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
          // Measuring crosshair: the crack overlay has to come off while
          // measuring (it swallows taps), so this is the only aiming guide.
          if (_measuring)
            Center(
              child: AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, __) => Opacity(
                  opacity: _pulseAnim.value,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add, color: Colors.amber, size: 56,
                          shadows: [Shadow(blurRadius: 4)]),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _measureStart == null
                              ? 'Aim at one end of the crack'
                              : 'Now the other end',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                        ),
                      ),
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
    ),
    );
  }
}
