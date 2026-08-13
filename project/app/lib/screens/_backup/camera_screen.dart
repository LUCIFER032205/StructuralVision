import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../scan_api.dart';
import 'batch_screen.dart';
import 'history_screen.dart';
import 'result_screen.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

// Burst capture presented as video recording: users tap "record", we take
// still photos on an interval instead (full-res JPEGs beat mp4 frames for
// crack detection, and the backend only sampled ~1 frame/sec anyway).
const _burstStartDelay = Duration(seconds: 1); // users aim after hitting record
const _burstInterval = Duration(milliseconds: 2500); // time to reposition
const _burstMaxShots = 8;

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  String? _status; // null = idle, otherwise progress text
  String? _initError;
  Timer? _burstTimer;
  List<Uint8List>? _burstShots; // non-null while "recording"

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
      // medium (~720p) keeps uploads small; YOLO input is 640px so higher res is wasted
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
    if (ctrl == null ||
        !ctrl.value.isInitialized ||
        _status != null ||
        _burstShots != null) {
      return;
    }
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
      // Multi-select: one image = normal flow, several = batch of scans.
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

  /// "Video" scan: looks like recording (tap to start/stop), but captures
  /// still photos every [_burstInterval] — one scan per shot, shown as a batch.
  Future<void> _toggleRecording() async {
    if (_burstShots != null) return _stopBurst();
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _status != null) return;
    setState(() => _burstShots = []); // REC state on immediately
    _burstTimer = Timer(_burstStartDelay, () {
      _takeBurstShot();
      _burstTimer =
          Timer.periodic(_burstInterval, (_) => _takeBurstShot());
    });
  }

  Future<void> _takeBurstShot() async {
    final ctrl = _controller;
    final shots = _burstShots;
    if (ctrl == null || !ctrl.value.isInitialized || shots == null) {
      _cancelBurst();
      return;
    }
    try {
      final shot = await ctrl.takePicture();
      shots.add(await shot.readAsBytes());
      if (mounted) setState(() {}); // tick the REC counter
      if (shots.length >= _burstMaxShots) await _stopBurst();
    } catch (_) {
      // transient camera hiccup — skip this shot, keep bursting
    }
  }

  Future<void> _stopBurst() async {
    final shots = _burstShots;
    _cancelBurst();
    if (shots == null || shots.isEmpty) return; // stopped before first shot
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
    _burstTimer = null;
    _burstShots = null;
    if (mounted) setState(() {});
  }

  Future<void> _openBatch(List<String> scanIds) async {
    if (!mounted) return;
    // Release the camera before leaving (ARCore needs exclusive access from
    // the result screens' AR view).
    final c = _controller;
    _controller = null;
    await c?.dispose();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BatchScreen(scanIds: scanIds)));
    if (mounted) _init();
  }

  Future<void> _analyze(Uint8List bytes) async {
    setState(() => _status = 'Uploading…');
    final scanId = await scanApi.submitScan(bytes);

    setState(() => _status = 'Analyzing…');
    final result = await scanApi.waitForResult(scanId);

    if (!mounted) return;
    // Release the camera before leaving — ARCore needs exclusive camera
    // access; holding it here SIGSEGVs libarcore_c.so on the AR screen.
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Scan failed: $e')));
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
    final ctrl = _controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan element'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HistoryScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
      body: _initError != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_initError!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _init, child: const Text('Retry')),
                ],
              ),
            )
          : ctrl == null || !ctrl.value.isInitialized
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(ctrl),
                if (_burstShots != null)
                  Positioned(
                    top: 16,
                    left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.fiber_manual_record,
                              color: Colors.red, size: 16),
                          const SizedBox(width: 6),
                          Text('REC · ${_burstShots!.length}',
                              style: const TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                if (_status != null)
                  Container(
                    color: Colors.black54,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Text(_status!,
                              style: const TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FloatingActionButton(
            heroTag: 'gallery',
            onPressed: _pickFromGallery,
            child: const Icon(Icons.photo_library),
          ),
          const SizedBox(width: 24),
          FloatingActionButton.large(
            heroTag: 'camera',
            onPressed: _scan,
            child: const Icon(Icons.camera_alt),
          ),
          const SizedBox(width: 24),
          FloatingActionButton(
            heroTag: 'video',
            tooltip: 'Record video scan',
            backgroundColor: _burstShots != null ? Colors.red : null,
            onPressed: _toggleRecording,
            child: Icon(_burstShots != null ? Icons.stop : Icons.videocam),
          ),
        ],
      ),
    );
  }
}
