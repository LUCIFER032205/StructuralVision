import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models.dart';
import '../scan_api.dart';
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
      final url = full.imageUrl;
      if (url == null) throw Exception('no photo stored for this scan');
      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan history')),
      body: FutureBuilder<List<ScanResult>>(
        future: _scans,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Could not load history: ${snap.error}',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () =>
                        setState(() => _scans = scanApi.listScans()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final scans = snap.data!;
          if (scans.isEmpty) {
            return const Center(child: Text('No scans yet'));
          }
          return ListView.separated(
            itemCount: scans.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final s = scans[i];
              final risk = s.riskLevel ?? '—';
              final color = riskColors[risk] ?? Colors.grey;
              final when = s.createdAt?.toLocal();
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: color,
                  child: Text(risk == '—' ? '?' : risk[0],
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                title: Text(
                    '${s.componentType ?? s.status} · ${s.crackCount ?? 0} cracks'),
                subtitle: Text(when != null
                    ? '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')} '
                        '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}'
                    : s.status),
                trailing: s.isDone ? const Icon(Icons.chevron_right) : null,
                onTap: s.isDone ? () => _open(s) : null,
              );
            },
          );
        },
      ),
    );
  }
}
