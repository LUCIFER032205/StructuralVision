import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../scan_api.dart';
import '../theme.dart';
import 'batch_screen.dart';
import 'component_select_sheet.dart';
import 'history_screen.dart';
import 'result_screen.dart';
import 'site_preview_screen.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

const _burstStartDelay = Duration(seconds: 1);
const _burstInterval   = Duration(milliseconds: 2500);
const _burstMaxShots   = 8;
const _multiMaxShots   = 12;

/// One queued shot in multi-capture mode: the photo plus the component the
/// user had selected when it was taken, so one session can mix wall, column…
class _Shot {
  final Uint8List bytes;
  final String component;
  const _Shot(this.bytes, this.component);
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  String? _status;
  String? _initError;
  // Two ways to collect several photos, deliberately different:
  //   burst  — timed auto-capture, one component for the whole sweep
  //   multi  — manual shutter, component re-pickable between shots
  Timer?  _burstTimer;
  List<Uint8List>? _burstShots;
  String? _burstComponent;
  List<_Shot>? _shots;   // non-null while multi-capture is on
  double _zoom = 1.0;
  double _zoomMin = 1.0, _zoomMax = 1.0;
  double _zoomAtGestureStart = 1.0;
  // Past 3.5x digital zoom only upscales blur; below 0.5x there is no lens.
  static const _kZoomFloor = 0.5, _kZoomCeiling = 3.5;
  // Remembered across scans and app restarts; the viewfinder chip changes it.
  // Asked for only when unset, instead of a modal before every capture.
  String? _component;
  static const _kComponent = 'last_component';

  @override
  void initState() {
    super.initState();
    _init();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _component = p.getString(_kComponent));
    });
  }

  Future<String?> _pickComponent() async {
    final picked =
        await ComponentSelectSheet.show(context, selected: _component);
    if (picked != null && mounted) {
      setState(() => _component = picked);
      (await SharedPreferences.getInstance()).setString(_kComponent, picked);
    }
    return picked;
  }

  // ── Zoom ────────────────────────────────────────────────────────────────
  void _onZoomStart() => _zoomAtGestureStart = _zoom;

  Future<void> _onZoomUpdate(double scale) async {
    final ctrl = _controller;
    if (ctrl == null || _zoomMax <= _zoomMin) return;
    final z = (_zoomAtGestureStart * scale).clamp(_zoomMin, _zoomMax);
    if ((z - _zoom).abs() < 0.01) return;
    setState(() => _zoom = z);
    await ctrl.setZoomLevel(z);
  }

  Future<void> _setZoom(double z) async {
    final ctrl = _controller;
    if (ctrl == null) return;
    z = z.clamp(_zoomMin, _zoomMax);
    setState(() => _zoom = z);
    await ctrl.setZoomLevel(z);
  }

  Future<String?> _ensureComponent() async =>
      _component ?? await _pickComponent();

  Future<void> _init() async {
    setState(() => _initError = null);
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw Exception('no camera found');
      final back = cams.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cams.first);
      // ResolutionPreset.high is 1280x720, NOT 1080p as previously commented —
      // every stored app scan from the 2026-09-15 device test came back
      // 720x1280, i.e. the model was UPSCALING them to imgsz 1024. veryHigh
      // is 1920x1080, so hairline cracks survive to inference. Inference cost
      // is unchanged (still imgsz 1024); only the upload is bigger.
      // ...except veryHigh STILL gave 720x1280 on the vivo V2307 (2026-09-22
      // test, all 24 scans): CameraX fell back below the 1080p bound. max
      // lets CameraX take the largest JPEG the bound streams allow.
      // ponytail: full-res upload (~3-5 MB/photo); downscale on-device to
      // ~2k long edge if bursts over ngrok get slow.
      _controller = CameraController(back, ResolutionPreset.max,
          enableAudio: false);
      await _controller!.initialize();
      // Zoom like a stock camera: open at 1x, pinch in to 3.5x, pinch out
      // to 0.5x. Below 1x only works where CameraX exposes the ultrawide as
      // part of a logical camera (min ratio < 1); elsewhere the floor is 1x.
      _zoomMin = (await _controller!.getMinZoomLevel())
          .clamp(_kZoomFloor, 1.0);
      _zoomMax = (await _controller!.getMaxZoomLevel())
          .clamp(1.0, _kZoomCeiling);
      _zoom = 1.0;
      await _controller!.setZoomLevel(_zoom);
    } catch (e) {
      _initError = 'Camera unavailable: $e';
    }
    if (mounted) setState(() {});
  }

  /// Shutter. In multi-capture mode it queues the shot with whatever component
  /// is selected right now and stays on the camera; otherwise it scans at once.
  Future<void> _scan() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized ||
        _status != null || _burstShots != null) {
      return;
    }

    final component = await _ensureComponent();
    if (component == null || !mounted) return; // user dismissed

    try {
      HapticFeedback.mediumImpact(); // gloved hands: confirm the shutter fired
      final shots = _shots;
      if (shots != null) {
        if (shots.length >= _multiMaxShots) {
          _showSnack('Max $_multiMaxShots photos — tap ✓ to analyze');
          return;
        }
        final bytes = await (await ctrl.takePicture()).readAsBytes();
        if (!mounted) return;
        setState(() => shots.add(_Shot(bytes, component)));
        return;
      }
      setState(() => _status = 'Capturing…');
      final shot = await ctrl.takePicture();
      await _analyze(await shot.readAsBytes(), componentType: component);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _status = null);
    }
  }

  Future<void> _pickFromGallery() async {
    if (_status != null || _shots != null || _burstShots != null) return;
    try {
      final picked = await ImagePicker().pickMultiImage();
      if (picked.isEmpty || !mounted) return;

      // Current component applies to all picked images
      final component = await _ensureComponent();
      if (component == null || !mounted) return;

      if (picked.length == 1) {
        await _analyze(await picked.first.readAsBytes(),
            componentType: component);
        return;
      }
      setState(() => _status = 'Uploading ${picked.length} images…');
      final ids = <String>[];
      for (final p in picked) {
        ids.add(await scanApi.submitScan(await p.readAsBytes(),
            componentType: component));
      }
      await _openBatch(ids);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _status = null);
    }
  }

  // ── Video burst: timed auto-capture, one component for the sweep ────────
  Future<void> _toggleRecording() async {
    if (_burstShots != null) return _stopBurst();
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized ||
        _status != null || _shots != null) {
      return;
    }

    // All burst frames inherit the current component
    final component = await _ensureComponent();
    if (component == null || !mounted) return;
    HapticFeedback.mediumImpact();

    setState(() {
      _burstShots     = [];
      _burstComponent = component;
    });
    _burstTimer = Timer(_burstStartDelay, () {
      _takeBurstShot();
      _burstTimer = Timer.periodic(_burstInterval, (_) => _takeBurstShot());
    });
  }

  Future<void> _takeBurstShot() async {
    final ctrl  = _controller;
    final shots = _burstShots;
    if (ctrl == null || !ctrl.value.isInitialized || shots == null) {
      _cancelBurst();
      return;
    }
    try {
      final shot = await ctrl.takePicture();
      shots.add(await shot.readAsBytes());
      if (mounted) setState(() {});
      if (shots.length >= _burstMaxShots) await _stopBurst();
    } catch (_) {}
  }

  Future<void> _stopBurst() async {
    final shots     = _burstShots;
    final component = _burstComponent;
    _cancelBurst();
    if (shots == null || shots.isEmpty) return;
    try {
      setState(() => _status = 'Uploading ${shots.length} images…');
      final ids = <String>[];
      for (final s in shots) {
        ids.add(await scanApi.submitScan(s, componentType: component));
      }
      await _openBatch(ids);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _status = null);
    }
  }

  void _cancelBurst() {
    _burstTimer?.cancel();
    _burstTimer     = null;
    _burstShots     = null;
    _burstComponent = null;
    if (mounted) setState(() {});
  }

  // ── Multi-capture: manual shutter, component re-pickable per shot ───────
  /// Enter multi-capture, or finish it and analyze the queue.
  Future<void> _toggleMulti() async {
    if (_shots == null) {
      final ctrl = _controller;
      if (ctrl == null || !ctrl.value.isInitialized ||
          _status != null || _burstShots != null) {
        return;
      }
      HapticFeedback.mediumImpact();
      setState(() => _shots = []);
      return;
    }
    await _finishMulti();
  }

  Future<void> _finishMulti() async {
    final shots = _shots;
    setState(() => _shots = null);
    if (shots == null || shots.isEmpty) return;
    try {
      setState(() => _status = 'Uploading ${shots.length} photos…');
      final ids = <String>[];
      for (final s in shots) {
        ids.add(await scanApi.submitScan(s.bytes, componentType: s.component));
      }
      await _openBatch(ids);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _status = null);
    }
  }

  void _removeShot(int i) {
    final shots = _shots;
    if (shots == null || i >= shots.length) return;
    setState(() => shots.removeAt(i));
  }

  Future<void> _openBatch(List<String> scanIds) async {
    if (!mounted) return;
    final c = _controller;
    _controller = null;
    await c?.dispose();
    if (!mounted) return;
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BatchScreen(scanIds: scanIds)));
    if (mounted) _init();
  }

  // Camera must be released before ARCore opens (holding it SIGSEGVs libarcore_c.so).
  Future<void> _openSitePreview() async {
    final c = _controller;
    _controller = null;
    await c?.dispose();
    if (!mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SitePreviewScreen()));
    if (mounted) _init();
  }

  Future<void> _analyze(Uint8List bytes, {required String componentType}) async {
    setState(() => _status = 'Uploading…');
    final scanId = await scanApi.submitScan(bytes, componentType: componentType);
    setState(() => _status = 'Analyzing…');
    final result = await scanApi.waitForResult(scanId);
    if (!mounted) return;
    final ctrl = _controller;
    _controller = null;
    await ctrl?.dispose();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ResultScreen(result: result, imageBytes: bytes)));
    if (mounted) _init();
  }

  void _showError(Object e) => _showSnack('Scan failed: $e');

  void _showSnack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  void dispose() {
    _burstTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl        = _controller;
    final shots       = _shots;
    final isMulti     = shots != null;
    final isRecording = _burstShots != null;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.radar, color: AppColors.accent, size: 18),
            const SizedBox(width: 8),
            Text('StructuralVision',
                style: AppTextStyles.titleMd.copyWith(color: Colors.white)),
          ],
        ),
        actions: [
          _NavAction(
            icon: Icons.history_rounded,
            label: 'History',
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HistoryScreen())),
          ),
          _NavAction(
            icon: Icons.apartment_rounded,
            label: 'Site preview (3D)',
            onTap: _openSitePreview,
          ),
          _NavAction(
            icon: Icons.logout_rounded,
            label: 'Sign out',
            onTap: () => Supabase.instance.client.auth.signOut(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _initError != null
          ? _ErrorBody(error: _initError!, onRetry: _init)
          : ctrl == null || !ctrl.value.isInitialized
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.accent))
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    // ── Live preview (pinch to zoom) ─────────────────────
                    GestureDetector(
                      onScaleStart: (_) => _onZoomStart(),
                      onScaleUpdate: (d) => _onZoomUpdate(d.scale),
                      child: CameraPreview(ctrl),
                    ),

                    // ── Viewfinder overlay ────────────────────────────────
                    if (_status == null && !isRecording) const _ViewfinderGuide(),

                    // ── Component chip (what's being scanned) ─────────────
                    // Stays tappable in multi-capture: each photo is queued
                    // with whatever component is selected at that moment.
                    if (_status == null && !isRecording)
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 64,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: _ComponentChip(
                            label: _component == null
                                ? 'Choose component'
                                : ComponentSelectSheet.labelFor(_component),
                            onTap: _pickComponent,
                          ),
                        ),
                      ),

                    // ── REC badge (video burst) ───────────────────────────
                    if (isRecording)
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 64,
                        left: 0,
                        right: 0,
                        child: Center(
                            child: _RecBadge(count: _burstShots!.length)),
                      ),

                    // ── Zoom presets (pinch on the preview for in-between) ─
                    if (_status == null && _zoomMax > _zoomMin)
                      Positioned(
                        right: 12,
                        top: MediaQuery.of(context).padding.top + 120,
                        bottom: 240, // clear of the multi-capture shot strip
                        child: _ZoomPresets(
                          zoom: _zoom,
                          min: _zoomMin,
                          max: _zoomMax,
                          onSelect: _setZoom,
                        ),
                      ),

                    // ── Queued shots (multi-capture) ──────────────────────
                    if (isMulti && _status == null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 150 + MediaQuery.of(context).padding.bottom,
                        child: _ShotStrip(
                            shots: shots, onRemove: _removeShot),
                      ),

                    // ── Processing overlay ────────────────────────────────
                    if (_status != null)
                      _ProcessingOverlay(status: _status!),

                    // ── Bottom controls ───────────────────────────────────
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _ControlBar(
                        multiCount: isMulti ? shots.length : null,
                        isRecording: isRecording,
                        isBusy: _status != null,
                        onGallery: _pickFromGallery,
                        onCapture: _scan,
                        onMulti: _toggleMulti,
                        onRecord: _toggleRecording,
                      ),
                    ),
                  ],
                ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _NavAction extends StatelessWidget {
  final IconData icon;
  final String   label;
  final VoidCallback onTap;

  const _NavAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      tooltip: label,
      onPressed: onTap,
      style: IconButton.styleFrom(
        foregroundColor: Colors.white70,
      ),
    );
  }
}

class _ViewfinderGuide extends StatelessWidget {
  const _ViewfinderGuide();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CustomPaint(
        size: const Size(200, 200),
        painter: _CornerPainter(),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.8)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const len = 20.0;
    final r   = size;
    // corners
    for (final pts in [
      [Offset(0, len), Offset.zero, Offset(len, 0)],
      [Offset(r.width - len, 0), Offset(r.width, 0), Offset(r.width, len)],
      [Offset(r.width, r.height - len), Offset(r.width, r.height), Offset(r.width - len, r.height)],
      [Offset(len, r.height), Offset(0, r.height), Offset(0, r.height - len)],
    ]) {
      final path = Path()..moveTo(pts[0].dx, pts[0].dy)
        ..lineTo(pts[1].dx, pts[1].dy)
        ..lineTo(pts[2].dx, pts[2].dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

class _RecBadge extends StatelessWidget {
  final int count;
  const _RecBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _PulsingDot(),
          const SizedBox(width: 8),
          Text(
            'REC · $count / $_burstMaxShots',
            style: AppTextStyles.bodyMd.copyWith(
                color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() { _ac.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ac,
      child: Container(
        width: 8, height: 8,
        decoration: const BoxDecoration(
          color: AppColors.danger,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// Thumbnails of the photos queued in multi-capture, each tagged with the
/// component chosen for it. Tap one to drop it before analyzing.
class _ShotStrip extends StatelessWidget {
  final List<_Shot> shots;
  final void Function(int) onRemove;
  const _ShotStrip({required this.shots, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    if (shots.isEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.6)),
          ),
          child: Text(
            'Multi-capture on — change the component between shots',
            style: AppTextStyles.bodySm.copyWith(color: Colors.white),
          ),
        ),
      );
    }
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: shots.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final s = shots[i];
          return Semantics(
            button: true,
            label: 'Photo ${i + 1}, '
                '${ComponentSelectSheet.labelFor(s.component)}. Tap to remove',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () => onRemove(i),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(s.bytes,
                            width: 56, height: 56, fit: BoxFit.cover),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close_rounded,
                              size: 14, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    width: 60,
                    child: Text(
                      ComponentSelectSheet.labelFor(s.component),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySm
                          .copyWith(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Stock-camera zoom buttons. The one closest to the live factor is lit and
/// shows the exact value, so a pinch to 1.7x reads "1.7x" on the 2x button.
class _ZoomPresets extends StatelessWidget {
  final double zoom, min, max;
  final ValueChanged<double> onSelect;
  const _ZoomPresets({
    required this.zoom,
    required this.min,
    required this.max,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final presets = <double>[
      if (min < 1) min,
      1,
      if (max >= 2) 2,
      if (max > 2) max,
    ];
    final active = presets.reduce(
        (a, b) => (zoom - a).abs() <= (zoom - b).abs() ? a : b);
    String fmt(double v) {
      final r = (v * 10).round() / 10;
      return '${r.toStringAsFixed(r == r.roundToDouble() ? 0 : 1)}x';
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Highest zoom on top, like the physical direction of "in".
        for (final p in presets.reversed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Semantics(
              button: true,
              label: 'Zoom ${fmt(p)}',
              child: GestureDetector(
                onTap: () => onSelect(p),
                child: Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.55),
                    border: p == active
                        ? Border.all(color: AppColors.accent, width: 1.5)
                        : null,
                  ),
                  child: Text(
                    p == active ? fmt(zoom) : fmt(p),
                    style: AppTextStyles.bodySm.copyWith(
                      color: p == active ? AppColors.accent : Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ProcessingOverlay extends StatelessWidget {
  final String status;
  const _ProcessingOverlay({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          color: AppColors.surface,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.accent),
              const SizedBox(height: 16),
              Text(status,
                  style: AppTextStyles.bodyMd.copyWith(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ControlBar extends StatelessWidget {
  /// null = single-shot mode; otherwise how many photos are queued.
  final int? multiCount;
  final bool isRecording;
  final bool isBusy;
  final VoidCallback onGallery;
  final VoidCallback onCapture;
  final VoidCallback onMulti;
  final VoidCallback onRecord;

  const _ControlBar({
    required this.multiCount,
    required this.isRecording,
    required this.isBusy,
    required this.onGallery,
    required this.onCapture,
    required this.onMulti,
    required this.onRecord,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    // One mode at a time: while a burst is running, multi is locked out, and
    // vice versa, so the two never fight over the shutter.
    final busyOrMulti  = isBusy || multiCount != null;
    final busyOrRec    = isBusy || isRecording;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 20, 12, 20 + bottom),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.85),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Gallery
          _SideButton(
            icon: Icons.photo_library_outlined,
            label: 'Gallery',
            onTap: (busyOrRec || multiCount != null) ? null : onGallery,
          ),

          // Multi-capture: queue photos, re-picking the component between shots
          _SideButton(
            icon: multiCount == null
                ? Icons.burst_mode_outlined
                : Icons.check_rounded,
            label: multiCount == null
                ? 'Multi'
                : multiCount == 0
                    ? 'Cancel'
                    : 'Analyze $multiCount',
            activeColor: multiCount != null ? AppColors.accent : null,
            onTap: busyOrRec ? null : onMulti,
          ),

          // Shutter
          _ShutterButton(onTap: busyOrRec ? null : onCapture),

          // Video burst: timed sweep, one component for all frames
          _SideButton(
            icon: isRecording ? Icons.stop_rounded : Icons.videocam_outlined,
            label: isRecording ? 'Stop' : 'Video',
            activeColor: isRecording ? AppColors.danger : null,
            onTap: busyOrMulti ? null : onRecord,
          ),
        ],
      ),
    );
  }
}

class _ComponentChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ComponentChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Component: $label. Tap to change',
      excludeSemantics: true,
      child: Material(
        color: Colors.black.withValues(alpha: 0.6),
        shape: StadiumBorder(
            side: BorderSide(color: AppColors.accent.withValues(alpha: 0.6))),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: AppTextStyles.titleSm
                          .copyWith(color: Colors.white)),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down_rounded,
                      color: AppColors.accent),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _ShutterButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: 'Capture photo',
      child: Material(
        type: MaterialType.transparency,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: Colors.white24,
          child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
              color: onTap != null ? AppColors.accent : AppColors.textMuted,
              width: 3),
        ),
        child: Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: onTap != null ? AppColors.accent : AppColors.textMuted,
            ),
          ),
        ),
      ),
        ),
      ),
    );
  }
}

class _SideButton extends StatelessWidget {
  final IconData icon;
  final String   label;
  /// Non-null when this button's mode is active — accent for multi-capture,
  /// danger for a running video burst.
  final Color?   activeColor;
  final VoidCallback? onTap;

  const _SideButton({
    required this.icon,
    required this.label,
    this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = onTap == null
        ? AppColors.textMuted
        : activeColor ?? Colors.white;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.12),
                  border: Border.all(
                      color: activeColor?.withValues(alpha: 0.6) ??
                          Colors.white.withValues(alpha: 0.2)),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 6),
              // Fixed width: four buttons now share the bar, and the widest
              // label ("Analyze 12") must not push the row past the screen.
              SizedBox(
                width: 72,
                child: Text(label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySm
                        .copyWith(color: color, fontSize: 11)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorBody({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(kPagePadding),
        child: AppCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.camera_alt_outlined,
                  color: AppColors.textMuted, size: 48),
              const SizedBox(height: 16),
              Text(error,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMd
                      .copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 20),
              FilledButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
                onPressed: onRetry,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
