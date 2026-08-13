import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models.dart';
import '../scan_api.dart';
import '../theme.dart';
import 'result_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<ScanResult>> _scans;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _scans = scanApi.listScans();
  }

  Future<void> _open(ScanResult scan) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final full = await scanApi.getScan(scan.id);
      final url  = full.imageUrl;
      if (url == null) throw Exception('no photo stored for this scan');
      final res  = await http.get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw Exception('photo download failed');
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) =>
              ResultScreen(result: full, imageBytes: res.bodyBytes)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not open scan: $e')));
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    final d = dt.toLocal();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}  '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan history'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () =>
                setState(() => _scans = scanApi.listScans()),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: FutureBuilder<List<ScanResult>>(
        future: _scans,
        builder: (context, snap) {
          if (snap.hasError) {
            return _centred(AppCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined,
                      color: AppColors.textMuted, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Could not load history',
                    style: AppTextStyles.titleMd,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${snap.error}',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySm,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Retry'),
                    onPressed: () =>
                        setState(() => _scans = scanApi.listScans()),
                  ),
                ],
              ),
            ));
          }

          if (!snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.accent));
          }

          final scans = snap.data!;
          if (scans.isEmpty) {
            return _centred(AppCard(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.document_scanner_outlined,
                      color: AppColors.textMuted, size: 48),
                  const SizedBox(height: 16),
                  Text('No scans yet', style: AppTextStyles.titleMd),
                  const SizedBox(height: 6),
                  Text('Capture a structural element to get started.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySm),
                ],
              ),
            ));
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(
                horizontal: kPagePadding, vertical: 16),
            itemCount: scans.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final s     = scans[i];
              final risk  = s.riskLevel ?? '—';
              final isDone = s.isDone;
              return AppCard(
                onTap: isDone ? () => _open(s) : null,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    // Risk / status indicator
                    risk == '—'
                        ? Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: AppColors.surface2,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Center(
                              child: SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.accent),
                              ),
                            ),
                          )
                        : RiskBadge(risk),

                    const SizedBox(width: 14),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.componentType ?? s.status,
                            style: AppTextStyles.titleSm
                                .copyWith(color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              if (s.crackCount != null) ...[
                                Text('${s.crackCount} cracks',
                                    style: AppTextStyles.bodySm),
                                const SizedBox(width: 8),
                                Container(
                                    width: 3,
                                    height: 3,
                                    decoration: const BoxDecoration(
                                      color: AppColors.textMuted,
                                      shape: BoxShape.circle,
                                    )),
                                const SizedBox(width: 8),
                              ],
                              Text(_formatDate(s.createdAt),
                                  style: AppTextStyles.mono
                                      .copyWith(fontSize: 11)),
                            ],
                          ),
                        ],
                      ),
                    ),

                    if (isDone)
                      const Icon(Icons.chevron_right,
                          color: AppColors.textMuted, size: 18),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _centred(Widget child) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(kPagePadding),
        child: child,
      ),
    );
  }
}
