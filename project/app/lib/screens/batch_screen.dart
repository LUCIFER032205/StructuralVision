import 'package:flutter/material.dart';

import '../models.dart';
import '../scan_api.dart';
import '../theme.dart';
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

  @override
  Widget build(BuildContext context) {
    final done  = _results.where((r) => r != null).length;
    final total = _results.length;
    final progress = total == 0 ? 0.0 : done / total;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Batch scan'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
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
        ],
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
                  'Segment ${index + 1}  ·  ${r.componentType ?? '?'}',
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
