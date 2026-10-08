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
  int? _walk; // detection index the walkthrough is on; null = not walking
  List<int> get _numbers =>
      List.generate(result.detections.length, (i) => result.numberOf(i));

  /// Tape reading for one crack: the only route for wall, column and beam
  /// cracks, since ARCore's vertical-plane mode SIGSEGVs on the vivo.
  Future<double?> _askLength(int i) async {
    final controller = TextEditingController();
    return showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Crack ${result.numberOf(i)} length'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Measure this crack end to end with a tape and enter it in '
              'centimetres. This scales the photo so its width can be graded.',
              style: AppTextStyles.bodySm,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Length', suffixText: 'cm'),
              onSubmitted: (v) => Navigator.of(ctx)
                  .pop(double.tryParse(v.trim().replaceAll(',', '.'))),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(
                double.tryParse(controller.text.trim().replaceAll(',', '.'))),
            child: const Text('Grade'),
          ),
        ],
      ),
    );
  }

  Future<void> _measure(int i, {required bool ar}) async {
    final double? cm;
    if (ar) {
      final photo = await _image;
      if (!mounted) return;
      cm = await Navigator.of(context).push<double>(MaterialPageRoute(
          builder: (_) =>
              ArScreen(result: result, photo: photo, measureCrack: i)));
    } else {
      cm = await _askLength(i);
    }
    if (cm == null || !mounted) return;
    if (cm <= 0 || cm > 1000) {
      _snack('Enter a length between 0 and 1000 cm');
      return;
    }
    await _send(() => scanApi.submitCrackMeasurement(
        result.id, result.detections[i].id, cm!));
  }

  Future<void> _setStatus(int i, String status) => _send(() =>
      scanApi.setCrackStatus(result.id, result.detections[i].id, status));

  /// One request, then redraw and, mid-walkthrough, move to the next crack.
  Future<void> _send(Future<ScanResult> Function() call) async {
    setState(() => _grading = true);
    try {
      final updated = await call();
      if (!mounted) return;
      setState(() {
        result = updated;
        if (_walk != null) {
          _walk = result.nextToMeasure;
          if (_walk == null) _snack('All cracks done');
        }
      });
    } on MeasurementRejected catch (e) {
      _snack(e.message, seconds: 5);
    } catch (e) {
      _snack('Could not save: $e');
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

  Future<void> _openAr() async {
    // Already decoded for the screen above; AR shows it as the "find this
    // crack" reference, since the live view has no idea which crack it is.
    final photo = await _image;
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ArScreen(result: result, photo: photo)));
  }

  /// Per-crack actions from a Details row.
  Future<void> _crackActions(int i) async {
    final d = result.detections[i];
    final pick = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      // Default cap is 9/16 of the screen: five rows overflowed and pushed
      // Reset under the system nav bar.
      isScrollControlled: true,
      builder: (ctx) {
        Widget tile(String v, IconData icon, String title, String sub) =>
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: kPagePadding),
              leading: Icon(icon, color: AppColors.accent),
              title: Text(title, style: AppTextStyles.titleMd),
              subtitle: Text(sub, style: AppTextStyles.bodySm),
              onTap: () => Navigator.of(ctx).pop(v),
            );
        return SafeArea(
          child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            tile('ar', Icons.view_in_ar, 'Measure in AR',
                'Floor and slab cracks'),
            tile('tape', Icons.edit_outlined, 'Enter length',
                'Walls, columns, beams, measured with a tape'),
            // Backend ignores a skip on a measured crack, so don't offer it.
            if (!d.isSkipped && !d.isMeasured)
              tile('skipped', Icons.redo_rounded, 'Skip',
                  'Keep it, mark it not measured'),
            if (!d.isDismissed)
              tile('not_crack', Icons.block_rounded, 'Not a crack',
                  'Remove a false alarm'),
            if (!d.isTodo)
              tile('todo', Icons.undo_rounded, 'Reset', 'Back to to-do'),
          ])),
        );
      },
    );
    if (pick == null || !mounted) return;
    if (pick == 'ar' || pick == 'tape') {
      await _measure(i, ar: pick == 'ar');
    } else {
      await _setStatus(i, pick);
    }
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
    final noCracks = result.activeBySize.isEmpty;

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
                                  result.detections, color, _walk ?? _selected,
                                  numbers: _numbers),
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
                          'Crack ${result.numberOf(_selected!)}: '
                          '${(result.detections[_selected!].confidence * 100).toStringAsFixed(0)}% confident · '
                          '${result.detections[_selected!].crackType == 'paint' ? 'surface/paint' : 'structural'}',
                          style: AppTextStyles.bodyMd
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),

                    if (_walk != null)
                      _walkPanel(_walk!)
                    else if (result.nextToMeasure != null) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        icon: const Icon(Icons.straighten, size: 18),
                        label: Text(result.measuredCount == 0
                            ? 'Measure cracks'
                            : 'Continue measuring'),
                        onPressed: _grading
                            ? null
                            : () => setState(() => _walk = result.nextToMeasure),
                      ),
                    ],

                    if (result.detections.isNotEmpty) ...[
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
                        // Capped so a wall with many cracks scrolls here
                        // instead of squeezing the photo out.
                        child: _showDetails
                            ? ConstrainedBox(
                                constraints: BoxConstraints(
                                    maxHeight:
                                        MediaQuery.of(context).size.height * 0.3),
                                child: SingleChildScrollView(child: _details()))
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
      return result.detections.isEmpty
          ? 'No cracks detected. Hairlines in poor light can be missed, '
              're-scan closer if you can see one.'
          : 'Every detection was dismissed as not a crack.';
    }
    final active = result.activeBySize.length;
    if (result.isMeasured) {
      final worst = result.worstMeasured;
      final head = worst == null
          ? 'Measured: ${result.widthSummary} · ${result.gradeSummary}'
          : 'Worst: crack ${result.numberOf(result.detections.indexOf(worst))}'
              ' · ${worst.widthSummary} · ${result.gradeSummary}';
      return '$head · ${result.measuredCount} of $active measured';
    }
    final area = ((result.crackAreaRatio ?? 0) * 100).toStringAsFixed(2);
    return '$active crack${active == 1 ? '' : 's'} · $area% of surface · preliminary';
  }

  String _rowText(CrackDetection d) {
    if (d.isDismissed) return 'not a crack';
    if (d.isSkipped) return 'skipped';
    if (!d.isMeasured) return 'to do';
    return '${d.lengthCm!.toStringAsFixed(0)} cm · ${d.widthSummary} · '
        '${d.gradeSummary}';
  }

  Widget _walkPanel(int i) {
    final active = result.activeBySize;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
              'Crack ${result.numberOf(i)} · '
              '${active.indexOf(i) + 1} of ${active.length}',
              style: AppTextStyles.titleMd),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.view_in_ar, size: 18),
                label: const Text('AR'),
                onPressed: _grading ? null : () => _measure(i, ar: true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                icon: _grading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.bg))
                    : const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Tape'),
                onPressed: _grading ? null : () => _measure(i, ar: false),
              ),
            ),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            TextButton(
                onPressed: _grading ? null : () => _setStatus(i, 'skipped'),
                child: const Text('Skip')),
            TextButton(
                onPressed: _grading ? null : () => _setStatus(i, 'not_crack'),
                child: const Text('Not a crack')),
            TextButton(
                onPressed: () => setState(() => _walk = null),
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary),
                child: const Text('Stop')),
          ]),
        ],
      ),
    );
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
        for (final i in result.bySize)
          InkWell(
            onTap: _grading ? null : () => _crackActions(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [
                SizedBox(
                  width: 28,
                  child: Text('${result.numberOf(i)}',
                      style: AppTextStyles.titleSm),
                ),
                Expanded(
                  child: Text(_rowText(result.detections[i]),
                      style: result.detections[i].isDismissed
                          ? AppTextStyles.bodySm.copyWith(
                              decoration: TextDecoration.lineThrough)
                          : AppTextStyles.bodyMd),
                ),
                if (result.detections[i].riskLevel != null)
                  RiskBadge(result.detections[i].riskLevel!),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textMuted),
              ]),
            ),
          ),
        if (paint > 0)
          line(Icons.format_paint_outlined,
              '$paint of ${result.detections.length} look like surface/paint '
              'cracks, likely cosmetic (shown in grey).'),
        line(Icons.touch_app_outlined,
            "Tap a crack for the model's confidence. A fainter outline means "
            'it is less sure. Tap a row to measure, skip or dismiss it.'),
      ],
    );
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
  /// Crack number per detection index (largest = 1); null draws no numbers.
  final List<int>?       numbers;

  CrackOverlayPainter(this.image, this.detections, this.color, this.selected,
      {this.numbers});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImage(image, Offset.zero, Paint());
    // Stroke scales with image size so it stays visible on 4000px photos.
    final unit = size.longestSide / 1024;

    for (var i = 0; i < detections.length; i++) {
      final d = detections[i];
      if (d.polygon.length < 3 || d.isDismissed) continue;
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
      final n = numbers?[i];
      if (n != null) _label(canvas, '$n', path.getBounds().topLeft, unit, isSel);
    }
  }

  void _label(Canvas canvas, String text, Offset at, double unit, bool sel) {
    final r = 16 * unit;
    // Clamped inside the photo: a crack touching the top edge cut its badge in half.
    final centre = Offset(
        (at.dx - r * 0.4).clamp(r, image.width - r).toDouble(),
        (at.dy - r * 0.4).clamp(r, image.height - r).toDouble());
    canvas.drawCircle(
        centre, r, Paint()..color = sel ? Colors.white : Colors.black87);
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              color: sel ? Colors.black : Colors.white,
              fontSize: 18 * unit,
              fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, centre - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CrackOverlayPainter old) =>
      old.image != image ||
      old.detections != detections ||
      old.selected != selected ||
      old.color != color ||
      old.numbers != numbers;
}
