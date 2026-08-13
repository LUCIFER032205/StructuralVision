import 'package:flutter/material.dart';

import '../models.dart';
import '../scan_api.dart';
import 'result_screen.dart';

/// Results for a multi-image upload or video scan: one row per segment,
/// each opens the normal ResultScreen.
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
    final done = _results.where((r) => r != null).length;
    return Scaffold(
      appBar: AppBar(
          title: Text('Segments ($done/${_results.length} analyzed)')),
      body: ListView.separated(
        itemCount: _results.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final r = _results[i];
          if (r == null) {
            return ListTile(
              leading: const SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2)))),
              title: Text('Segment ${i + 1}'),
              subtitle: const Text('Analyzing…'),
            );
          }
          if (r.isError) {
            return ListTile(
              leading: const CircleAvatar(
                  backgroundColor: Colors.grey,
                  child: Icon(Icons.error, color: Colors.white)),
              title: Text('Segment ${i + 1} — failed'),
              subtitle: Text(r.error ?? 'unknown error'),
            );
          }
          final risk = r.riskLevel ?? 'LOW';
          final color = riskColors[risk] ?? Colors.grey;
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: color,
              child: Text(risk[0],
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            title: Text(
                'Segment ${i + 1} · ${r.componentType ?? '?'} · ${r.crackCount ?? 0} cracks'),
            subtitle: Text(
                '$risk · area ${((r.crackAreaRatio ?? 0) * 100).toStringAsFixed(2)}%'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(r),
          );
        },
      ),
    );
  }
}
