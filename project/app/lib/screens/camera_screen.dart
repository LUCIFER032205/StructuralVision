import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../scan_api.dart';
import '../theme.dart';
import 'batch_screen.dart';
import 'history_screen.dart';
import 'result_screen.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

const _burstStartDelay = Duration(seconds: 1);
const _burstInterval   = Duration(milliseconds: 2500);
const _burstMaxShots   = 8;

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  String? _status;
  String? _initError;
  Timer?  _burstTimer;
  List<Uint8List>? _burstShots;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() => _initError = null);
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw Exception('no camera found');
      final back = cams.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cams.first);
      _controller = CameraController(back, ResolutionPreset.medium,
          enableAudio: false);
      await _controller!.initialize();
    } catch (e) {
      _initError = 'Camera unavailable: $e';
    }
    if (mounted) setState(() {});
  }

  Future<void> _scan() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized ||
        _status != null || _burstShots != null) return;
    try {
      setState(() => _status = 'Capturing…');
      final shot = await ctrl.takePicture();
      await _analyze(await shot.readAsBytes());
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _status = null);
    }
  }

  Future<void> _pickFromGallery() async {
    if (_status != null || _burstShots != null) return;
    try {
      final picked = await ImagePicker().pickMultiImage();
      if (picked.isEmpty) return;
      if (picked.length == 1) {
        await _analyze(await picked.first.readAsBytes());
        return;
      }
      setState(() => _status = 'Uploading ${picked.length} images…');
      final ids = <String>[];
      for (final p in picked) {
        ids.add(await scanApi.submitScan(await p.readAsBytes()));
      }
      await _openBatch(ids);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _status = null);
    }
  }

  Future<void> _toggleRecording() async {
    if (_burstShots != null) return _stopBurst();
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _status != null) return;
    setState(() => _burstShots = []);
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
    final shots = _burstShots;
    _cancelBurst();
    if (shots == null || shots.isEmpty) return;
    try {
      setState(() => _status = 'Uploading ${shots.length} images…');
      final ids = <String>[];
      for (final s in shots) {
        ids.add(await scanApi.submitScan(s));
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
    _burstTimer  = null;
    _burstShots  = null;
    if (mounted) setState(() {});
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

  Future<void> _analyze(Uint8List bytes) async {
    setState(() => _status = 'Uploading…');
    final scanId = await scanApi.submitScan(bytes);
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

  void _showError(Object e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan failed: $e')));
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
    final ctrl      = _controller;
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
                    // ── Live preview ─────────────────────────────────────
                    CameraPreview(ctrl),

                    // ── Viewfinder overlay ────────────────────────────────
                    if (_status == null && !isRecording)
                      const _ViewfinderGuide(),

                    // ── REC badge ─────────────────────────────────────────
                    if (isRecording)
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 64,
                        left: 0,
                        right: 0,
                        child: Center(child: _RecBadge(count: _burstShots!.length)),
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
                        isRecording: isRecording,
                        isBusy: _status != null,
                        onGallery: _pickFromGallery,
                        onCapture: _scan,
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
  final bool isRecording;
  final bool isBusy;
  final VoidCallback onGallery;
  final VoidCallback onCapture;
  final VoidCallback onRecord;

  const _ControlBar({
    required this.isRecording,
    required this.isBusy,
    required this.onGallery,
    required this.onCapture,
    required this.onRecord,
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

          // Record
          _SideButton(
            icon: isRecording ? Icons.stop_rounded : Icons.videocam_outlined,
            label: isRecording ? 'Stop' : 'Video',
            accent: isRecording,
            onTap: isBusy ? null : onRecord,
          ),
        ],
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _ShutterButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
            ? AppColors.danger
            : Colors.white;
    return GestureDetector(
      onTap: onTap,
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
                      ? AppColors.danger.withValues(alpha: 0.6)
                      : Colors.white.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: AppTextStyles.bodySm.copyWith(color: color, fontSize: 11)),
        ],
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
