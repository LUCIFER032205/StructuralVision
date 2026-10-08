import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../building_catalog.dart';
import '../photo_orientation.dart';
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

/// What the shutter does, picked from the Photo · Multi · Video switch.
enum _Mode { photo, multi, video }

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
  List<_Shot>? _shots;   // non-null exactly while _mode is multi
  _Mode _mode = _Mode.photo;
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
      _zoom = 1.0.clamp(_zoomMin, _zoomMax);
      // Best effort: a device whose minimum zoom sits above 1.0 must not
      // fail camera init just because the opening zoom level couldn't apply.
      try {
        await _controller!.setZoomLevel(_zoom);
      } catch (_) {}
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
        final bytes = await takeUprightPicture(ctrl);
        if (!mounted) return;
        setState(() => shots.add(_Shot(bytes, component)));
        return;
      }
      setState(() => _status = 'Capturing…');
      await _analyze(await takeUprightPicture(ctrl), componentType: component);
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
      shots.add(await takeUprightPicture(ctrl));
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
  void _setMode(_Mode m) {
    if (m == _mode || _status != null || _burstShots != null) return;
    if (_shots?.isNotEmpty ?? false) {
      _showSnack('Analyze or remove the queued photos first');
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _mode  = m;
      _shots = m == _Mode.multi ? [] : null;
    });
  }

  Future<void> _finishMulti() async {
    final shots = _shots;
    if (shots == null || shots.isEmpty) return;
    setState(() => _shots = []); // stay in Multi for the next set
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

  /// Every screen opened from here can reach AR (history -> result -> AR,
  /// batch -> result -> AR, site preview), and ARCore SIGSEGVs in
  /// libarcore_c.so if CameraX still owns the camera: CameraX answers
  /// ERROR_CAMERA_IN_USE by reopening it a second later and taking it back.
  /// So the camera is released for every push, not just some of them.
  Future<void> _pushWithoutCamera(Widget screen) async {
    if (!mounted) return;
    final c = _controller;
    _controller = null;
    setState(() {});
    await c?.dispose();
    if (!mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen));
    // The reverse race: ARCore closes its camera session on a background
    // thread after the AR route is gone. Reopening CameraX straight away
    // evicts that session mid-close and ARCore's own teardown throws
    // "Session has been closed" uncaught, killing the app (3 crashes on the
    // vivo 2026-10-06, each ~0.3 s after CameraX began OPENING).
    // ponytail: fixed delay, the plugin gives no "camera released" signal;
    // a CameraManager.AvailabilityCallback channel would make it exact.
    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted) _init();
  }

  Future<void> _openBatch(List<String> scanIds) =>
      _pushWithoutCamera(BatchScreen(scanIds: scanIds));

  Future<void> _openSitePreview() async {
    // _status guard blocks a double tap from pushing two AR screens (two
    // ARCore sessions) while the up-to-8s fetch below is in flight.
    if (_status != null || _burstShots != null) return;
    setState(() => _status = 'Loading buildings…');
    try {
      // Fetch while the live preview is still up.
      final buildings = await BuildingCatalog.fetch();
      if (!mounted) return;
      setState(() => _status = null);
      await _pushWithoutCamera(SitePreviewScreen(buildings: buildings));
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _status = null);
    }
  }

  Future<void> _analyze(Uint8List bytes, {required String componentType}) async {
    setState(() => _status = 'Uploading…');
    final scanId = await scanApi.submitScan(bytes, componentType: componentType);
    setState(() => _status = 'Analyzing…');
    final result = await scanApi.waitForResult(scanId);
    if (!mounted) return;
    await _pushWithoutCamera(ResultScreen(result: result, imageBytes: bytes));
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
    final isRecording = _burstShots != null;
    final busy        = _status != null;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: false,
        titleSpacing: 12,
        // What's being scanned lives in the top bar; it stays tappable in
        // Multi, where each photo is queued with the component picked then.
        title: isRecording
            ? _RecBadge(count: _burstShots!.length)
            : _ComponentChip(
                label: _component == null
                    ? 'Choose component'
                    : ComponentSelectSheet.labelFor(_component),
                onTap: busy ? null : _pickComponent,
              ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'History',
            color: Colors.white70,
            onPressed: busy
                ? null
                : () => _pushWithoutCamera(const HistoryScreen()),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white70),
            tooltip: 'More',
            color: AppColors.surface2,
            onSelected: (v) => v == 'site'
                ? _openSitePreview()
                : Supabase.instance.client.auth.signOut(),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'site',
                child: ListTile(
                  leading: Icon(Icons.apartment_rounded),
                  title: Text('Site preview (3D)'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'signout',
                child: ListTile(
                  leading: Icon(Icons.logout_rounded),
                  title: Text('Sign out'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
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
                    // CameraPreview keeps the stream's aspect ratio only under
                    // loose constraints; filling the Stack stretched the 4:3
                    // stream (1632x1224 on the vivo) to 20:9, ~1.67x too tall.
                    // Top-aligned under the bar, like a stock camera in 4:3;
                    // the photo is 4:3 too, so the frame is what gets shot.
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onScaleStart: (_) => _onZoomStart(),
                      onScaleUpdate: (d) => _onZoomUpdate(d.scale),
                      child: Padding(
                        padding: EdgeInsets.only(
                            top: MediaQuery.of(context).padding.top +
                                kToolbarHeight),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: CameraPreview(ctrl),
                        ),
                      ),
                    ),

                    // Distance is the main detection failure: from a few metres
                    // a crack is a few pixels and groove lines/cables win.
                    if (!busy && !isRecording)
                      Positioned(
                        top: MediaQuery.of(context).padding.top + kToolbarHeight + 12,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Get close: fill the frame with the crack',
                                style: AppTextStyles.bodySm.copyWith(color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      ),

                    if (busy) _ProcessingOverlay(status: _status!),

                    // ── Bottom: shots · zoom · mode · shutter ────────────
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _BottomControls(
                        mode: _mode,
                        shots: shots,
                        isRecording: isRecording,
                        busy: busy,
                        zoom: _zoom,
                        zoomMin: _zoomMin,
                        zoomMax: _zoomMax,
                        onZoom: _setZoom,
                        onMode: _setMode,
                        onRemoveShot: _removeShot,
                        onGallery: _pickFromGallery,
                        onShutter:
                            _mode == _Mode.video ? _toggleRecording : _scan,
                        onAnalyze: _finishMulti,
                      ),
                    ),
                  ],
                ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'Each shot can have its own component',
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final p in presets)
          Semantics(
              button: true,
              label: 'Zoom ${fmt(p)}',
              child: GestureDetector(
                onTap: () => onSelect(p),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  // 48dp tap target around a 36dp lit circle.
                  width: 48,
                  height: 44,
                  alignment: Alignment.center,
                  child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p == active
                        ? Colors.black.withValues(alpha: 0.5)
                        : null,
                  ),
                  child: Text(
                    p == active ? fmt(zoom) : fmt(p),
                    style: AppTextStyles.bodySm.copyWith(
                      color: p == active ? AppColors.accent : Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
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

/// Everything under the preview, stacked like a stock camera: queued shots
/// (Multi), zoom row, mode switch, then gallery · shutter · analyze.
class _BottomControls extends StatelessWidget {
  final _Mode mode;
  final List<_Shot>? shots;
  final bool isRecording, busy;
  final double zoom, zoomMin, zoomMax;
  final ValueChanged<double> onZoom;
  final ValueChanged<_Mode> onMode;
  final void Function(int) onRemoveShot;
  final VoidCallback onGallery, onShutter, onAnalyze;

  const _BottomControls({
    required this.mode,
    required this.shots,
    required this.isRecording,
    required this.busy,
    required this.zoom,
    required this.zoomMin,
    required this.zoomMax,
    required this.onZoom,
    required this.onMode,
    required this.onRemoveShot,
    required this.onGallery,
    required this.onShutter,
    required this.onAnalyze,
  });

  @override
  Widget build(BuildContext context) {
    final queued = shots?.length ?? 0;
    return Container(
      padding: EdgeInsets.fromLTRB(
          0, 32, 0, 16 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (shots != null && !busy) ...[
            _ShotStrip(shots: shots!, onRemove: onRemoveShot),
            const SizedBox(height: 16),
          ],
          if (!busy && zoomMax > zoomMin) ...[
            _ZoomPresets(
                zoom: zoom, min: zoomMin, max: zoomMax, onSelect: onZoom),
            const SizedBox(height: 8),
          ],
          // Hidden mid-burst so a stray tap can't switch modes under it.
          Opacity(
            opacity: isRecording ? 0 : 1,
            child: IgnorePointer(
              ignoring: isRecording || busy,
              child: _ModeSwitch(mode: mode, onSelect: onMode),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Center(
                  child: _RoundButton(
                    icon: Icons.photo_library_outlined,
                    label: 'Pick from gallery',
                    onTap: mode == _Mode.photo && !busy ? onGallery : null,
                  ),
                ),
              ),
              _ShutterButton(
                mode: mode,
                isRecording: isRecording,
                onTap: busy ? null : onShutter,
              ),
              Expanded(
                child: Center(
                  child: queued > 0 && !busy
                      ? _RoundButton(
                          icon: Icons.check_rounded,
                          label: 'Analyze $queued photos',
                          badge: '$queued',
                          filled: true,
                          onTap: onAnalyze,
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  final _Mode mode;
  final ValueChanged<_Mode> onSelect;
  const _ModeSwitch({required this.mode, required this.onSelect});

  static const _labels = {
    _Mode.photo: 'Photo',
    _Mode.multi: 'Multi',
    _Mode.video: 'Video',
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final m in _Mode.values)
          Semantics(
            button: true,
            selected: m == mode,
            label: '${_labels[m]} mode',
            excludeSemantics: true,
            child: InkWell(
              onTap: () => onSelect(m),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text(
                  _labels[m]!,
                  style: AppTextStyles.titleSm.copyWith(
                    color: m == mode ? AppColors.accent : Colors.white70,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? badge;
  final bool filled;
  final VoidCallback? onTap;

  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: filled
            ? AppColors.accent
            : Colors.white.withValues(alpha: enabled ? 0.14 : 0.06),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled
              ? () {
                  HapticFeedback.selectionClick();
                  onTap!();
                }
              : null,
          child: SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon,
                    size: 24,
                    color: filled
                        ? AppColors.bg
                        : enabled
                            ? Colors.white
                            : Colors.white30),
                if (badge != null)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Text(badge!,
                        style: AppTextStyles.label.copyWith(
                            color: AppColors.bg,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ComponentChip extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
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
                  Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleSm
                            .copyWith(color: Colors.white)),
                  ),
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
  final _Mode mode;
  final bool isRecording;
  final VoidCallback? onTap;
  const _ShutterButton(
      {required this.mode, required this.isRecording, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fill = !enabled
        ? AppColors.textMuted
        : mode == _Mode.video
            ? AppColors.danger
            : AppColors.accent;
    return Semantics(
      button: true,
      enabled: enabled,
      label: mode == _Mode.video
          ? (isRecording ? 'Stop recording' : 'Start video burst')
          : mode == _Mode.multi
              ? 'Add photo'
              : 'Capture photo',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 76,
          height: 76,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
          ),
          // Recording morphs the dot into a stop square, like a stock camera.
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: isRecording ? 28 : 60,
            height: isRecording ? 28 : 60,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(isRecording ? 6 : 30),
            ),
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
