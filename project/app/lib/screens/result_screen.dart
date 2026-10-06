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
  bool _grading = false;
  bool _showDetails = false;

  /// Type a tape/ruler reading instead of measuring in AR. This is the only
  /// route for wall, column and beam cracks: ARCore's vertical-plane mode
  /// SIGSEGVs on the Vivo Y200, so AR measuring is floor/slab only.
  Future<void> _enterLengthManually() async {
    final controller = TextEditingController();
    final cm = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Crack length'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Measure the crack end to end with a tape or ruler and enter it '
              'in centimetres. This scales the photo so the width can be graded.',
              style: AppTextStyles.bodySm,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Length',
                suffixText: 'cm',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) =>
                  Navigator.of(ctx).pop(double.tryParse(v.trim())),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx)
                .pop(double.tryParse(controller.text.trim())),
            child: const Text('Grade'),
          ),
        ],
      ),
    );
    if (cm == null || !mounted) return;
    if (cm <= 0 || cm > 1000) {
      _snack('Enter a length between 0 and 1000 cm');
      return;
    }
    setState(() => _grading = true);
    try {
      final updated = await scanApi.submitMeasurement(result.id, cm);
      if (mounted) setState(() => result = updated);
    } on MeasurementRejected catch (e) {
      _snack(e.message, seconds: 5);
    } catch (e) {
      _snack('Could not grade measurement: $e');
    } finally {
      if (mounted) setState(() => _grading = false);
    }
  }

  void _snack(String msg, {int seconds = 3}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: Duration(seconds: seconds)));
    }
  }

  Future<void> _openAr({bool measure = false}) async {
    // Already decoded for the screen above; AR shows it as the "find this
    // crack" reference, since the live view has no idea which crack it is.
    final photo = await _image;
    if (!mounted) return;
    final updated = await Navigator.of(context).push<ScanResult>(
        MaterialPageRoute(
            builder: (_) => ArScreen(
                result: result, photo: photo, startMeasuring: measure)));
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
        actions: [
          IconButton(
            icon: const Icon(Icons.view_in_ar),
            tooltip: 'View in AR',
            onPressed: _openAr,
          ),
          IconButton(
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: 'Share report',
            onPressed: _shareReport,
          ),
          const SizedBox(width: 4),
        ],
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
                              painter: CrackOverlayPainter(img,
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
          // One summary line and one action up front; everything else sits
          // behind "Details" so the photo keeps most of the screen.
          Container(
            color: AppColors.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    kPagePadding, 20, kPagePadding, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            ComponentSelectSheet.labelFor(result.componentType),
                            style: AppTextStyles.titleLg,
                          ),
                        ),
                        const SizedBox(width: 12),
                        RiskBadge(risk),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(_summary(noCracks), style: AppTextStyles.bodySm),
                    // A range means the photo and the mask disagree on this
                    // crack; say so rather than imply precision.
                    if (result.isMeasured && result.widthUncertain)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          result.resolutionHint ??
                              'Width is a range — verify with a crack gauge',
                          style: AppTextStyles.bodySm
                              .copyWith(color: AppColors.riskMedium),
                        ),
                      ),
                    if (_selected != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Crack ${_selected! + 1}: '
                          '${(result.detections[_selected!].confidence * 100).toStringAsFixed(0)}% confident · '
                          '${result.detections[_selected!].crackType == 'paint' ? 'surface/paint' : 'structural'}',
                          style: AppTextStyles.bodyMd
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),

                    // Preliminary -> measured is the step that turns the
                    // estimate into a standards-based grade; keep it the one
                    // obvious button.
                    if (!noCracks && !result.isMeasured) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        icon: _grading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AppColors.bg))
                            : const Icon(Icons.straighten, size: 18),
                        label: const Text('Measure crack'),
                        onPressed: _grading ? null : _chooseMeasureMethod,
                      ),
                    ],

                    if (!noCracks) ...[
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: () =>
                            setState(() => _showDetails = !_showDetails),
                        style: TextButton.styleFrom(
                            foregroundColor: AppColors.textSecondary),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_showDetails ? 'Hide details' : 'Details'),
                            Icon(
                                _showDetails
                                    ? Icons.expand_less_rounded
                                    : Icons.expand_more_rounded,
                                size: 20),
                          ],
                        ),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        alignment: Alignment.topCenter,
                        child: _showDetails
                            ? _details()
                            : const SizedBox(width: double.infinity),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _summary(bool noCracks) {
    if (noCracks) {
      return 'No cracks detected. Hairlines in poor light can be missed, '
          're-scan closer if you can see one.';
    }
    if (result.isMeasured) {
      return 'Measured: ${result.widthSummary} · ${result.gradeSummary}';
    }
    final n = result.crackCount ?? 0;
    final area = ((result.crackAreaRatio ?? 0) * 100).toStringAsFixed(2);
    return '$n crack${n == 1 ? '' : 's'} · $area% of surface · preliminary';
  }

  Widget _details() {
    final paint =
        result.detections.where((d) => d.crackType == 'paint').length;
    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: AppTextStyles.bodySm)),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (paint > 0)
          line(Icons.format_paint_outlined,
              '$paint of ${result.detections.length} look like surface/paint '
              'cracks, likely cosmetic (shown in grey).'),
        line(Icons.touch_app_outlined,
            "Tap a crack for the model's confidence. A fainter outline means "
            'it is less sure.'),
      ],
    );
  }

  /// AR only sees floor/slab planes (vertical mode crashes ARCore on the
  /// Y200), so walls, columns and beams go through the tape-measure route.
  Future<void> _chooseMeasureMethod() async {
    final useAr = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: kPagePadding),
                leading: const Icon(Icons.view_in_ar, color: AppColors.accent),
                title: Text('Measure in AR', style: AppTextStyles.titleMd),
                subtitle: Text('Floor and slab cracks',
                    style: AppTextStyles.bodySm),
                onTap: () => Navigator.of(ctx).pop(true),
              ),
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: kPagePadding),
                leading:
                    const Icon(Icons.edit_outlined, color: AppColors.accent),
                title: Text('Enter length', style: AppTextStyles.titleMd),
                subtitle: Text('Walls, columns and beams, measured with a tape',
                    style: AppTextStyles.bodySm),
                onTap: () => Navigator.of(ctx).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
    if (useAr == null || !mounted) return;
    useAr ? await _openAr(measure: true) : await _enterLengthManually();
  }

  Future<void> _shareReport() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final pdf = await scanApi.getReport(result.id);
      await Printing.sharePdf(
          bytes: pdf, filename: 'scan_${result.id.substring(0, 8)}.pdf');
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Report failed: $e')));
    }
  }

  static Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    return (await codec.getNextFrame()).image;
  }
}

Path _pathOf(List<List<double>> polygon) {
  final path = Path()..moveTo(polygon[0][0], polygon[0][1]);
  for (final p in polygon.skip(1)) {
    path.lineTo(p[0], p[1]);
  }
  return path..close();
}

class CrackOverlayPainter extends CustomPainter {
  final ui.Image         image;
  final List<CrackDetection> detections;
  final Color            color;
  final int?             selected;

  CrackOverlayPainter(this.image, this.detections, this.color, this.selected);

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
  bool shouldRepaint(covariant CrackOverlayPainter old) =>
      old.image != image ||
      old.detections != detections ||
      old.selected != selected ||
      old.color != color;
}
