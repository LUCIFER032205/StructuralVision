import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'models.dart';

/// Client for the FastAPI backend. JWT comes from the live Supabase session.
class ScanApi {
  String get _jwt {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) throw StateError('not signed in');
    return session.accessToken;
  }

  /// POST /scan -> scan_id. One retry on network failure (Wi-Fi blip).
  /// Pass [prevScanId] to diff cracks against an earlier scan of the same surface.
  Future<String> submitScan(Uint8List imageBytes, {String? prevScanId}) async {
    for (var attempt = 0; ; attempt++) {
      try {
        final req = http.MultipartRequest(
            'POST', Uri.parse('${AppConfig.apiBase}/scan'))
          ..headers['Authorization'] = 'Bearer $_jwt'
          ..files.add(http.MultipartFile.fromBytes('image', imageBytes,
              filename: 'scan.jpg'));
        if (prevScanId != null) req.fields['prev_scan_id'] = prevScanId;
        final res = await http.Response.fromStream(
            await req.send().timeout(const Duration(seconds: 30)));
        if (res.statusCode != 200) {
          throw Exception('scan upload failed (${res.statusCode}): ${res.body}');
        }
        return (jsonDecode(res.body) as Map<String, dynamic>)['scan_id']
            as String;
      } on Exception {
        if (attempt >= 1) rethrow;
      }
    }
  }

  /// Fetch the stored scan photo (for result screens opened without local bytes).
  Future<Uint8List> getImage(String imageUrl) async {
    final res =
        await http.get(Uri.parse(imageUrl)).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw Exception('image fetch failed');
    return res.bodyBytes;
  }

  /// GET /scan/{id}
  Future<ScanResult> getScan(String scanId) async {
    final res = await http.get(
      Uri.parse('${AppConfig.apiBase}/scan/$scanId'),
      headers: {'Authorization': 'Bearer $_jwt'},
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('poll failed (${res.statusCode}): ${res.body}');
    }
    return ScanResult.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// GET /scans — user's scan history, newest first.
  Future<List<ScanResult>> listScans() async {
    final res = await http.get(
      Uri.parse('${AppConfig.apiBase}/scans'),
      headers: {'Authorization': 'Bearer $_jwt'},
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('history failed (${res.statusCode}): ${res.body}');
    }
    return (jsonDecode(res.body) as List)
        .map((j) => ScanResult.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// GET /scan/{id}/report -> PDF bytes.
  Future<Uint8List> getReport(String scanId) async {
    final res = await http.get(
      Uri.parse('${AppConfig.apiBase}/scan/$scanId/report'),
      headers: {'Authorization': 'Bearer $_jwt'},
    ).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('report failed (${res.statusCode}): ${res.body}');
    }
    return res.bodyBytes;
  }

  /// Poll every 2s until done/error. Tolerates transient poll failures;
  /// gives up after 2 minutes total.
  Future<ScanResult> waitForResult(String scanId) async {
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    Object? lastError;
    while (DateTime.now().isBefore(deadline)) {
      try {
        final scan = await getScan(scanId);
        if (scan.isDone || scan.isError) return scan;
        lastError = null;
      } on Exception catch (e) {
        lastError = e; // transient — keep polling until deadline
      }
      await Future.delayed(const Duration(seconds: 2));
    }
    throw Exception(lastError != null
        ? 'analysis polling failed: $lastError'
        : 'analysis timed out after 2 minutes');
  }
}

final scanApi = ScanApi();
