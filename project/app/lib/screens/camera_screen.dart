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

const _multiMaxShots = 12;

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
  List<_Shot>? _shots;   // non-null while multi-capture is on
  double _zoom = 1.0;
  double _zoomMin = 1.0, _zoomMax = 1.0;
  double _zoomAtGestureStart = 1.0;
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
      // high (~1080p): the model infers at 1024px, medium (~720p) upscaled
      // and could lose hairline cracks before inference.
      _controller = CameraController(back, ResolutionPreset.high,
          enableAudio: false);
      await _controller!.initialize();
      // Digital zoom: hairline cracks are easier to frame from a distance.
      _zoomMin = await _controller!.getMinZoomLevel();
      _zoomMax = await _controller!.getMaxZoomLevel();
      _zoom = _zoomMin;
    } catch (e) {
      _initError = 'Camera unavailable: $e';
    }
    if (mounted) setState(() {});
  }

  /// Shutter. In multi-capture mode it queues the shot with whatever component
  /// is selected right now and stays on the camera; otherwise it scans at once.
  Future<void> _scan() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _status != null) return;

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
    if (_status != null || _shots != null) return;
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

  /// Enter multi-capture, or finish it and analyze the queue.
  Future<void> _toggleMulti() async {
    if (_shots == null) {
      final ctrl = _controller;
      if (ctrl == null || !ctrl.value.isInitialized || _status != null) return;
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
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl    = _controller;
    final shots   = _shots;
    final isMulti = shots != null;

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
                    if (_status == null) const _ViewfinderGuide(),

                    // ── Component chip (what's being scanned) ─────────────
                    // Stays tappable in multi-capture: each photo is queued
                    // with whatever component is selected at that moment.
                    if (_status == null)
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

                    // ── Zoom control ──────────────────────────────────────
                    if (_status == null && _zoomMax > _zoomMin)
                      Positioned(
                        right: 12,
                        top: MediaQuery.of(context).padding.top + 120,
                        bottom: 240, // clear of the multi-capture shot strip
                        child: _ZoomBar(
                          zoom: _zoom,
                          min: _zoomMin,
                          max: _zoomMax,
                          onChanged: _setZoom,
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
                        isBusy: _status != null,
                        onGallery: _pickFromGallery,
                        onCapture: _scan,
                        onMulti: _toggleMulti,
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

/// Vertical zoom slider + live factor. Pinch on the preview does the same;
/// this gives a one-handed control and shows the current factor.
class _ZoomBar extends StatelessWidget {
  final double zoom, min, max;
  final ValueChanged<double> onChanged;
  const _ZoomBar({
    required this.zoom,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text('${zoom.toStringAsFixed(1)}x',
              style: AppTextStyles.bodySm.copyWith(color: Colors.white)),
        ),
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: Slider(
              value: zoom.clamp(min, max),
              min: min,
              max: max,
              activeColor: AppColors.accent,
              inactiveColor: Colors.white24,
              onChanged: onChanged,
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
  final bool isBusy;
  final VoidCallback onGallery;
  final VoidCallback onCapture;
  final VoidCallback onMulti;

  const _ControlBar({
    required this.multiCount,
    required this.isBusy,
    required this.onGallery,
    required this.onCapture,
    required this.onMulti,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 20 + bottom),
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
            onTap: isBusy ? null : onGallery,
          ),

          // Shutter
          _ShutterButton(onTap: isBusy ? null : onCapture),

          // Multi-capture: start queueing, or finish and analyze the queue
          _SideButton(
            icon: multiCount == null
                ? Icons.burst_mode_outlined
                : Icons.check_rounded,
            label: multiCount == null
                ? 'Multi'
                : multiCount == 0
                    ? 'Cancel'
                    : 'Analyze $multiCount',
            accent: multiCount != null,
            onTap: isBusy ? null : onMulti,
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
  final bool     accent;
  final VoidCallback? onTap;

  const _SideButton({
    required this.icon,
    required this.label,
    this.accent = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = onTap == null
        ? AppColors.textMuted
        : accent
            ? AppColors.accent
            : Colors.white;
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
                      color: accent
                          ? AppColors.accent.withValues(alpha: 0.6)
                          : Colors.white.withValues(alpha: 0.2)),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 6),
              Text(label,
                  style: AppTextStyles.bodySm.copyWith(color: color, fontSize: 12)),
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
