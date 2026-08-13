import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../models.dart';
import '../scan_api.dart';
import '../theme.dart';
import 'ar_screen.dart';

const riskColors = {
  'HIGH':   AppColors.riskHigh,
  'MEDIUM': AppColors.riskMedium,
  'LOW':    AppColors.riskLow,
};

class ResultScreen extends StatelessWidget {
  final ScanResult result;
  final Uint8List  imageBytes;

  const ResultScreen(
      {super.key, required this.result, required this.imageBytes});

  @override
  Widget build(BuildContext context) {
    if (result.isError) {
      return Scaffold(
        appBar: AppBar(title: const Text('Scan failed')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(kPagePadding),
            child: AppCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline,
                      color: AppColors.danger, size: 48),
                  const SizedBox(height: 16),
                  Text('Scan failed', style: AppTextStyles.titleMd),
                  const SizedBox(height: 8),
                  Text(result.error ?? 'unknown error',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMd
                          .copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final risk  = result.riskLevel ?? 'LOW';
    final color = riskColors[risk] ?? AppColors.textMuted;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Scan result'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          // ── Annotated image ────────────────────────────────────────────
          Expanded(
            child: FutureBuilder<ui.Image>(
              future: _decode(imageBytes),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.accent));
                }
                final img = snap.data!;
                return Container(
                  color: Colors.black,
                  child: FittedBox(
                    child: SizedBox(
                      width:  img.width.toDouble(),
                      height: img.height.toDouble(),
                      child: CustomPaint(
                        painter: _OverlayPainter(
                            img, result.detections, color),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // ── Result panel ───────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(kPagePadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Risk + component row
                    Row(
                      children: [
                        RiskBadge(risk, large: true),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                result.componentType ?? 'Unknown',
                                style: AppTextStyles.titleLg,
                              ),
                              if (result.componentConfidence != null)
                                Text(
                                  '${(result.componentConfidence! * 100).toStringAsFixed(0)}% confidence',
                                  style: AppTextStyles.bodySm,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Stats row
                    Row(
                      children: [
                        _StatChip(
                          label: 'CRACKS',
                          value: '${result.crackCount ?? 0}',
                        ),
                        const SizedBox(width: 10),
                        _StatChip(
                          label: 'AREA',
                          value:
                              '${((result.crackAreaRatio ?? 0) * 100).toStringAsFixed(2)}%',
                        ),
                        if (result.detections
                            .any((d) => d.crackType == 'paint')) ...[
                          const SizedBox(width: 10),
                          _StatChip(
                            label: 'SURFACE',
                            value:
                                '${result.detections.where((d) => d.crackType == 'paint').length}',
                            color: Colors.blueGrey,
                          ),
                        ],
                      ],
                    ),

                    // Paint crack note
                    if (result.detections.any((d) => d.crackType == 'paint'))
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.blueGrey.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.blueGrey
                                    .withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline,
                                  size: 14,
                                  color: Colors.blueGrey.shade400),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${result.detections.where((d) => d.crackType == 'paint').length} of ${result.detections.length} detections look like surface/paint — likely cosmetic (shown in grey)',
                                  style: AppTextStyles.bodySm.copyWith(
                                      color: Colors.blueGrey.shade400),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 16),

                    // Actions
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.view_in_ar, size: 18),
                            label: const Text('View in AR'),
                            onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        ArScreen(result: result))),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.picture_as_pdf, size: 18),
                            label: const Text('Share report'),
                            onPressed: () async {
                              final messenger =
                                  ScaffoldMessenger.of(context);
                              try {
                                final pdf =
                                    await scanApi.getReport(result.id);
                                await Printing.sharePdf(
                                    bytes: pdf,
                                    filename:
                                        'scan_${result.id.substring(0, 8)}.pdf');
                              } catch (e) {
                                messenger.showSnackBar(SnackBar(
                                    content: Text('Report failed: $e')));
                              }
                            },
                          ),
                        ),
                      ],
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

  static Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    return (await codec.getNextFrame()).image;
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _StatChip({
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.label),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppTextStyles.titleMd.copyWith(
              color: color != null
                  ? (color == Colors.blueGrey
                      ? Colors.blueGrey.shade300
                      : color)
                  : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  final ui.Image         image;
  final List<CrackDetection> detections;
  final Color            color;

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
