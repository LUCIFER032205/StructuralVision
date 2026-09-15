import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../models.dart';
import '../scan_api.dart';
import '../theme.dart';
import 'ar_screen.dart';
import 'component_select_sheet.dart';

const riskColors = {
  'HIGH':   AppColors.riskHigh,
  'MEDIUM': AppColors.riskMedium,
  'LOW':    AppColors.riskLow,
};

class ResultScreen extends StatefulWidget {
  final ScanResult result;
  final Uint8List  imageBytes;

  const ResultScreen(
      {super.key, required this.result, required this.imageBytes});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  // Replaced when the AR screen returns a measured (re-graded) scan.
  late ScanResult result = widget.result;
  late final Future<ui.Image> _image = _decode(widget.imageBytes);
  int? _selected; // tapped detection index, shows its confidence

  Future<void> _openAr({bool measure = false}) async {
    final updated = await Navigator.of(context).push<ScanResult>(
        MaterialPageRoute(
            builder: (_) => ArScreen(result: result, startMeasuring: measure)));
    if (updated != null && mounted) setState(() => result = updated);
  }

  void _onImageTap(Offset p) {
    // Topmost polygon containing the tap, in image pixel coordinates.
    int? hit;
    for (var i = 0; i < result.detections.length; i++) {
      final poly = result.detections[i].polygon;
      if (poly.length >= 3 && _pathOf(poly).contains(p)) hit = i;
    }
    setState(() => _selected = hit);
  }

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
    final noCracks = result.detections.isEmpty;

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
              future: _image,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.accent));
                }
                final img = snap.data!;
                // Pinch to zoom: hairline cracks are unreadable at fit-to-screen.
                return Container(
                  color: Colors.black,
                  child: InteractiveViewer(
                    maxScale: 8,
                    child: Center(
                      child: FittedBox(
                        child: GestureDetector(
                          onTapUp: (d) => _onImageTap(d.localPosition),
                          child: SizedBox(
                            width:  img.width.toDouble(),
                            height: img.height.toDouble(),
                            child: CustomPaint(
                              painter: _OverlayPainter(img,
                                  result.detections, color, _selected),
                            ),
                          ),
                        ),
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
                                ComponentSelectSheet.labelFor(
                                    result.componentType),
                                style: AppTextStyles.titleLg,
                              ),
                              if (!noCracks)
                                Text(
                                  result.isMeasured
                                      ? 'Measured: ${result.crackWidthMm!.toStringAsFixed(1)} mm · ${result.gradeSummary}'
                                      : 'Preliminary estimate from the photo',
                                  style: AppTextStyles.bodySm,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // A clean surface is a result, not an absence of one.
                    if (noCracks)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(kCardRadius),
                          border: Border.all(
                              color: AppColors.success.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.verified_outlined,
                                color: AppColors.success, size: 28),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('No cracks detected',
                                      style: AppTextStyles.titleMd),
                                  Text(
                                    'Hairline cracks in poor light can be missed — '
                                    're-scan closer if you can see one.',
                                    style: AppTextStyles.bodySm,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
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

                    // Tapped crack: model confidence
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        _selected == null
                            ? 'Tap a crack for model confidence · fainter outline = less sure'
                            : 'Crack ${_selected! + 1}: ${(result.detections[_selected!].confidence * 100).toStringAsFixed(0)}% confident · '
                                '${result.detections[_selected!].crackType == 'paint' ? 'surface/paint' : 'structural'}',
                        style: _selected == null
                            ? AppTextStyles.bodySm
                            : AppTextStyles.bodyMd
                                .copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    ],

                    const SizedBox(height: 16),

                    // Preliminary -> measured is the one step that turns the
                    // estimate into a standards-based grade; make it obvious.
                    if (!noCracks && !result.isMeasured) ...[
                      FilledButton.icon(
                        icon: const Icon(Icons.straighten, size: 18),
                        label: const Text('Measure crack for a JBDPA / BRE grade'),
                        onPressed: () => _openAr(measure: true),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Actions
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.view_in_ar, size: 18),
                            label: const Text('View in AR'),
                            onPressed: _openAr,
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

Path _pathOf(List<List<double>> polygon) {
  final path = Path()..moveTo(polygon[0][0], polygon[0][1]);
  for (final p in polygon.skip(1)) {
    path.lineTo(p[0], p[1]);
  }
  return path..close();
}

class _OverlayPainter extends CustomPainter {
  final ui.Image         image;
  final List<CrackDetection> detections;
  final Color            color;
  final int?             selected;

  _OverlayPainter(this.image, this.detections, this.color, this.selected);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImage(image, Offset.zero, Paint());
    // Stroke scales with image size so it stays visible on 4000px photos.
    final unit = size.longestSide / 1024;

    for (var i = 0; i < detections.length; i++) {
      final d = detections[i];
      if (d.polygon.length < 3) continue;
      // Backend keeps detections at conf >= 0.4: map 0.4..1 -> 0..1 so a
      // weak detection draws thin and faint, a strong one thick and solid.
      final t = ((d.confidence - 0.4) / 0.6).clamp(0.0, 1.0);
      final c = d.crackType == 'paint' ? Colors.blueGrey : color;
      final isSel = i == selected;
      final path = _pathOf(d.polygon);
      canvas.drawPath(path, Paint()..color = c.withValues(alpha: 0.15 + 0.25 * t));
      canvas.drawPath(
          path,
          Paint()
            ..color = isSel ? Colors.white : c.withValues(alpha: 0.45 + 0.55 * t)
            ..style = PaintingStyle.stroke
            ..strokeWidth = (isSel ? 5.0 : 1.5 + 3.5 * t) * unit);
    }
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter old) =>
      old.image != image ||
      old.detections != detections ||
      old.selected != selected ||
      old.color != color;
}
