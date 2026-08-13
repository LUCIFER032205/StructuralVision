import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../models.dart';
import '../scan_api.dart';
import 'ar_screen.dart';

const riskColors = {
  'HIGH': Colors.red,
  'MEDIUM': Colors.orange,
  'LOW': Colors.green,
};

class ResultScreen extends StatelessWidget {
  final ScanResult result;
  final Uint8List imageBytes;

  const ResultScreen(
      {super.key, required this.result, required this.imageBytes});

  @override
  Widget build(BuildContext context) {
    final risk = result.riskLevel ?? 'LOW';
    final color = riskColors[risk] ?? Colors.grey;

    if (result.isError) {
      return Scaffold(
        appBar: AppBar(title: const Text('Scan failed')),
        body: Center(child: Text(result.error ?? 'unknown error')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Scan result')),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<ui.Image>(
              future: _decode(imageBytes),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final img = snap.data!;
                return FittedBox(
                  child: SizedBox(
                    width: img.width.toDouble(),
                    height: img.height.toDouble(),
                    child: CustomPaint(
                      painter:
                          _OverlayPainter(img, result.detections, color),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: color.withValues(alpha: 0.15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Chip(
                      label: Text(risk,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                      backgroundColor: color,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${result.componentType ?? '?'} '
                      '(${((result.componentConfidence ?? 0) * 100).toStringAsFixed(0)}%)',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Cracks: ${result.crackCount ?? 0}   '
                    'Area: ${((result.crackAreaRatio ?? 0) * 100).toStringAsFixed(2)}%'),
                if (result.detections.any((d) => d.crackType == 'paint'))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${result.detections.where((d) => d.crackType == 'paint').length} '
                      'of ${result.detections.length} look like surface/paint cracks '
                      '(shown in grey) — likely cosmetic',
                      style: TextStyle(color: Colors.blueGrey.shade700),
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.view_in_ar),
                  label: const Text('View in AR'),
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => ArScreen(result: result))),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Share report'),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      final pdf = await scanApi.getReport(result.id);
                      await Printing.sharePdf(
                          bytes: pdf,
                          filename:
                              'scan_${result.id.substring(0, 8)}.pdf');
                    } catch (e) {
                      messenger.showSnackBar(
                          SnackBar(content: Text('Report failed: $e')));
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    return (await codec.getNextFrame()).image;
  }
}

class _OverlayPainter extends CustomPainter {
  final ui.Image image;
  final List<CrackDetection> detections;
  final Color color;

  _OverlayPainter(this.image, this.detections, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImage(image, Offset.zero, Paint());

    for (final d in detections) {
      if (d.polygon.length < 3) continue;
      final c = d.crackType == 'paint' ? Colors.blueGrey : color;
      final stroke = Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      final fill = Paint()..color = c.withValues(alpha: 0.3);
      final path = Path()..moveTo(d.polygon[0][0], d.polygon[0][1]);
      for (final p in d.polygon.skip(1)) {
        path.lineTo(p[0], p[1]);
      }
      path.close();
      canvas.drawPath(path, fill);
      canvas.drawPath(path, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter old) =>
      old.image != image || old.detections != detections;
}
