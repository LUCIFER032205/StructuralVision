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
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:vector_math/vector_math_64.dart' as vm;

import '../config.dart';
import '../models.dart';
import 'result_screen.dart' show CrackOverlayPainter, riskColors;
import 'component_select_sheet.dart';

/// Live AR view: tap a detected plane on the inspected element to pin a
/// 3D marker anchor; risk + component info shown as an overlay badge.
class ArScreen extends StatefulWidget {
  final ScanResult result;
  /// The scan photo, shown as a "find this crack" reference: the live view
  /// only sees the real crack once the camera is pointed at it.
  final ui.Image? photo;
  /// Detection index to measure (one crack per visit: the route pops with
  /// the tapped length in cm). Null = view mode, which only projects.
  final int? measureCrack;

  const ArScreen(
      {super.key, required this.result, this.photo, this.measureCrack});

  @override
  State<ArScreen> createState() => _ArScreenState();
}

class _ArScreenState extends State<ArScreen> with SingleTickerProviderStateMixin {
  ARSessionManager? _session;
  ARObjectManager? _objects;
  ARAnchorManager? _anchors;
  bool _placed = false;
  bool _planeFound = false;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;
  late bool _measuring = widget.measureCrack != null;
  vm.Vector3? _measureStart;
  // Wall planes: opt-in, because PlaneDetectionConfig.vertical SIGSEGVs in
  // libarcore_c.so on some devices (Vivo Y200, ARCore 1.54). A SIGSEGV can't
  // be caught in Dart, so instead a flag is written before switching and
  // cleared once the session survives; finding it still set on a later launch
  // means the app died there, and wall mode is disabled for good on this phone.
  bool _wallMode = false;
  bool _wallBlocked = false;
  static const _kWallPending = 'ar_wall_pending';
  static const _kWallBlocked = 'ar_wall_blocked';
  Timer? _wallProbe;
  // Starts as the scan's preliminary result; replaced by the backend's
  // standards-graded result (JBDPA / BRE 251) after a measurement. Width
  // conversion and grading live only in backend inference.py.
  ScanResult get _result => widget.result;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.5, end: 1.0).animate(_pulseCtrl);
    _loadWallState();
  }

  Future<void> _loadWallState() async {
    final prefs = await SharedPreferences.getInstance();
    var blocked = prefs.getBool(_kWallBlocked) ?? false;
    if (prefs.getBool(_kWallPending) ?? false) {
      // Last run enabled wall mode and never got to clear this — it crashed.
      blocked = true;
      await prefs.setBool(_kWallBlocked, true);
      await prefs.remove(_kWallPending);
    }
    if (mounted) setState(() => _wallBlocked = blocked);
  }

  Future<void> _toggleWallMode() async {
    final prefs = await SharedPreferences.getInstance();
    if (_wallMode) {
      _wallProbe?.cancel();
      await prefs.remove(_kWallPending);
      setState(() { _wallMode = false; _resetPlacement(); });
      return;
    }
    await prefs.setBool(_kWallPending, true);
    setState(() { _wallMode = true; _resetPlacement(); });
    // Survived long enough to be considered safe on this device.
    _wallProbe = Timer(const Duration(seconds: 8), () async {
      (await SharedPreferences.getInstance()).remove(_kWallPending);
    });
  }

  void _resetPlacement() {
    // Recreating ARView drops any placed node.
    _placed = false;
    _planeFound = false;
    // A wall-mode switch restarts the measurement, not the screen's purpose.
    _measuring = widget.measureCrack != null;
    _measureStart = null;
  }

  /// Small pin where the first tap landed, so point 1 is visible while
  /// aiming for the other end. The screen closes on the second tap.

  Future<void> _dropStartPin(vm.Matrix4 at) async {
    final anchor = ARPlaneAnchor(transformation: at);
    if (await _anchors?.addAnchor(anchor) != true) return;
    final pin = ARNode(
      type: NodeType.webGLB,
      uri: _markerUrl,
      scale: vm.Vector3.all(0.05), // 5 cm: visible, small enough to aim past
    );
    if (await _objects?.addNode(pin, planeAnchor: anchor) != true) {
      await _anchors?.removeAnchor(anchor);
    }
  }

  // Risk-colored pin GLBs generated into backend/static (see marker_*.glb)
  String get _markerUrl =>
      '${AppConfig.apiBase}/static/marker_${(_result.riskLevel ?? 'LOW').toLowerCase()}.glb';

  // Per-scan crack-overlay quad (transparent texture with the crack polygons),
  // built on demand by the backend. Only meaningful when cracks were found.
  bool get _hasCracks => widget.result.activeBySize.isNotEmpty;

  /// Real size of the projected crack pattern once any crack is measured:
  /// the photo's longest side times the photo's measured mm-per-pixel.
  double? get _trueSizeM {
    final mmpp = widget.result.trueSizeMmPerPx;
    final photo = widget.photo;
    if (mmpp == null || photo == null) return null;
    return (photo.width > photo.height ? photo.width : photo.height) * mmpp / 1000;
  }
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
        _dropStartPin(hit.worldTransform);
        _toast('Point 1 set — tap the other end of the crack');
      } else {
        // One crack per visit: hand the length back; the result screen
        // submits it and moves the walkthrough on.
        Navigator.of(context).pop(_measureStart!.distanceTo(p) * 100);
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
      scale: vm.Vector3.all(_hasCracks ? (_trueSizeM ?? 1.0) : 0.2),
    );
    if (await _objects?.addNode(node, planeAnchor: anchor) != true) {
      await _anchors?.removeAnchor(anchor);
      setState(() => _placed = false);
      _toast('Marker failed to load — check backend connection');
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
    _wallProbe?.cancel();
    if (_wallMode) {
      // Left cleanly, so this device handles wall planes fine.
      SharedPreferences.getInstance().then((p) => p.remove(_kWallPending));
    }
    _pulseCtrl.dispose();
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final risk = _result.riskLevel ?? 'LOW';
    final color = riskColors[risk] ?? Colors.grey;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AR inspection'),
        actions: [
          if (!_wallBlocked)
            IconButton(
              tooltip: _wallMode
                  ? 'Wall planes on — switch back to flat surfaces'
                  : 'Also detect wall planes (may not work on every phone)',
              icon: Icon(_wallMode
                  ? Icons.border_vertical
                  : Icons.border_horizontal),
              onPressed: _toggleWallMode,
            ),
        ],
      ),
      body: Stack(
        children: [
          ARView(
            key: ValueKey(_wallMode),
            onARViewCreated: _onARViewCreated,
            // HORIZONTAL already covers every flat surface the phone can sit
            // square to — desk, table, floor, slab, ceiling — since ARCore
            // reports all of those as horizontal planes. Walls need VERTICAL,
            // which is the opt-in above.
            planeDetectionConfig: _wallMode
                ? PlaneDetectionConfig.horizontalAndVertical
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
                      '$risk RISK${_result.isMeasured ? '' : ' (preliminary)'} — ${ComponentSelectSheet.labelFor(_result.componentType)}',
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
                              ? 'Crack ${_result.numberOf(widget.measureCrack!)} of '
                                  '${_result.activeBySize.length}: point the camera at '
                                  'the real crack shown bottom-left, then tap one end'
                              : 'Now tap the other end of the same crack',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold))
                    else if (!_planeFound)
                      Row(
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                                _wallMode
                                    ? 'Sweep across the wall — textured areas work best'
                                    : 'Sweep across any flat surface — desk, floor or slab',
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
                              fontStyle: FontStyle.italic))
                    else if (_hasCracks && _trueSizeM == null)
                      const Text('Not to scale — measure a crack to show real size',
                          style: TextStyle(
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
                              ? 'Tap one end of the real crack'
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

          if (widget.photo != null && _hasCracks)
            Positioned(
              left: 12,
              // The AR view runs under the gesture bar; clear it.
              bottom: 16 + MediaQuery.of(context).padding.bottom,
              child: _CrackReference(
                photo: widget.photo!,
                detections: _result.detections,
                color: color,
                selected: widget.measureCrack,
                numbers: List.generate(
                    _result.detections.length, (i) => _result.numberOf(i)),
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


/// The scan photo with its detections outlined: what to look for in the live
/// view. Tap to see it full size.
class _CrackReference extends StatelessWidget {
  final ui.Image photo;
  final List<CrackDetection> detections;
  final Color color;
  final int? selected;
  final List<int> numbers;
  const _CrackReference(
      {required this.photo,
      required this.detections,
      required this.color,
      required this.selected,
      required this.numbers});

  Widget _image() => FittedBox(
        child: SizedBox(
          width: photo.width.toDouble(),
          height: photo.height.toDouble(),
          child: CustomPaint(
              painter: CrackOverlayPainter(photo, detections, color, selected,
                  numbers: numbers)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Scan photo with the crack outlined. Tap to enlarge',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => showDialog(
          context: context,
          builder: (ctx) => Dialog(
            backgroundColor: Colors.black,
            insetPadding: const EdgeInsets.all(16),
            child: GestureDetector(
              onTap: () => Navigator.of(ctx).pop(),
              child: InteractiveViewer(maxScale: 6, child: _image()),
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 112,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(color: Colors.black54, blurRadius: 8)
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: photo.width / photo.height,
                  child: _image(),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Find this crack',
                  style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}
