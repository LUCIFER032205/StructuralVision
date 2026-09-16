import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../models.dart';
import '../scan_api.dart';
import '../theme.dart';
import 'component_select_sheet.dart';
import 'result_screen.dart';

class BatchScreen extends StatefulWidget {
  final List<String> scanIds;
  const BatchScreen({super.key, required this.scanIds});

  @override
  State<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends State<BatchScreen> {
  late final List<ScanResult?> _results =
      List.filled(widget.scanIds.length, null);
  bool _opening = false;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < widget.scanIds.length; i++) {
      scanApi.waitForResult(widget.scanIds[i]).then((r) {
        if (mounted) setState(() => _results[i] = r);
      }).catchError((e) {
        if (mounted) {
          setState(() => _results[i] =
              ScanResult(id: widget.scanIds[i], status: 'error', error: '$e'));
        }
      });
    }
  }

  Future<void> _open(ScanResult scan) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final url = scan.imageUrl;
      if (url == null) throw Exception('no photo stored for this segment');
      final bytes = await scanApi.getImage(url);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ResultScreen(result: scan, imageBytes: bytes)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not open: $e')));
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  /// One PDF for the whole session: summary table of every photo and the
  /// component it was scanned as, then a detail page each.
  Future<void> _shareReport() async {
    final ids = [
      for (var i = 0; i < _results.length; i++)
        if (_results[i]?.isDone ?? false) widget.scanIds[i]
    ];
    if (ids.isEmpty || _sharing) return;
    setState(() => _sharing = true);
    try {
      final pdf = await scanApi.getBatchReport(ids);
      await Printing.sharePdf(
          bytes: pdf, filename: 'inspection_${ids.first.substring(0, 8)}.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Report failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final done  = _results.where((r) => r != null).length;
    final total = _results.length;
    final progress = total == 0 ? 0.0 : done / total;
    final ready = _results.where((r) => r?.isDone ?? false).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Batch scan'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      // One bottom inset for the whole screen: without it the last card sat
      // under the Android gesture/nav bar and was half cut off.
      body: SafeArea(
        top: false,
        child: Column(
        children: [
          // ── Progress header ────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(
                kPagePadding, 16, kPagePadding, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('$done of $total analyzed',
                        style: AppTextStyles.titleSm),
                    Text('${(progress * 100).toStringAsFixed(0)}%',
                        style: AppTextStyles.titleSm
                            .copyWith(color: AppColors.accent)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: AppColors.border,
                    valueColor: const AlwaysStoppedAnimation(AppColors.accent),
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          // ── List ───────────────────────────────────────────────────────
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(
                  horizontal: kPagePadding, vertical: 8),
              itemCount: _results.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final r = _results[i];
                return _SegmentCard(
                  index: i,
                  result: r,
                  onTap: (r != null && !r.isError) ? () => _open(r) : null,
                );
              },
            ),
          ),
          // ── Combined report ────────────────────────────────────────────
          if (ready > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  kPagePadding, 0, kPagePadding, 12),
              child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: _sharing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.picture_as_pdf, size: 18),
                    label: Text(_sharing
                        ? 'Building report…'
                        : 'Share full report ($ready photos)'),
                  onPressed: _sharing ? null : _shareReport,
                ),
              ),
            ),
        ],
        ),
      ),
    );
  }
}

class _SegmentCard extends StatelessWidget {
  final int index;
  final ScanResult? result;
  final VoidCallback? onTap;

  const _SegmentCard({
    required this.index,
    required this.result,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final r = result;

    // Pending
    if (r == null) {
      return AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.accent),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Segment ${index + 1}',
                    style: AppTextStyles.titleSm
                        .copyWith(color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text('Analyzing…', style: AppTextStyles.bodySm),
              ],
            ),
          ],
        ),
      );
    }

    // Error
    if (r.isError) {
      return AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.error_outline,
                  color: AppColors.danger, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Segment ${index + 1} — failed',
                      style: AppTextStyles.titleSm
                          .copyWith(color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(r.error ?? 'unknown error',
                      style: AppTextStyles.bodySm,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Done
    final risk  = r.riskLevel ?? 'LOW';
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          RiskBadge(risk),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Segment ${index + 1}  ·  ${ComponentSelectSheet.labelFor(r.componentType)}',
                  style: AppTextStyles.titleSm
                      .copyWith(color: AppColors.textPrimary),
                ),
                const SizedBox(height: 3),
                Text(
                  '${r.crackCount ?? 0} cracks  ·  '
                  '${((r.crackAreaRatio ?? 0) * 100).toStringAsFixed(2)}% area',
                  style: AppTextStyles.bodySm,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right,
              color: AppColors.textMuted, size: 18),
        ],
      ),
    );
  }
}
