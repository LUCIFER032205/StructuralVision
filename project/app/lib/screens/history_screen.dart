import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models.dart';
import '../scan_api.dart';
import '../theme.dart';
import 'component_select_sheet.dart';
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
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) =>
              ResultScreen(result: full, imageBytes: res.bodyBytes)));
      // Measure / skip / dismiss on that screen changes the risk shown here.
      if (mounted) setState(() => _scans = scanApi.listScans());
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
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final d = dt.toLocal();
    return '${d.day} ${months[d.month - 1]}, '
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

          // Plain rows with hairline dividers: a list of scans is one list,
          // not a stack of separate cards.
          return ListView.separated(
            padding: EdgeInsets.only(
                top: 8, bottom: 16 + MediaQuery.of(context).padding.bottom),
            itemCount: scans.length,
            separatorBuilder: (_, __) =>
                const Divider(indent: kPagePadding, endIndent: kPagePadding),
            itemBuilder: (context, i) {
              final s      = scans[i];
              final risk   = s.riskLevel;
              final isDone = s.isDone;
              final n      = s.crackCount;
              return InkWell(
                onTap: isDone ? () => _open(s) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: kPagePadding, vertical: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.componentType != null
                                  ? ComponentSelectSheet.labelFor(
                                      s.componentType)
                                  : s.status,
                              style: AppTextStyles.titleMd,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [
                                if (n != null) '$n crack${n == 1 ? '' : 's'}',
                                _formatDate(s.createdAt),
                              ].join('  ·  '),
                              style: AppTextStyles.bodySm,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      if (risk != null)
                        RiskBadge(risk)
                      else if (s.isError)
                        const RiskBadge('FAILED')
                      else
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.accent),
                        ),
                    ],
                  ),
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
