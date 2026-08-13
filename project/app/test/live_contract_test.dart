import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:structural_vision_ar/models.dart';

void main() {
  test('ScanResult parses a real live backend response', () {
    final json = jsonDecode(
        File('test/live_scan_result.json').readAsStringSync());
    final scan = ScanResult.fromJson(json as Map<String, dynamic>);
    expect(scan.isDone, true);
    expect(scan.componentType, isNotNull);
    expect(scan.riskLevel, isIn(['LOW', 'MEDIUM', 'HIGH']));
    expect(scan.detections, isNotEmpty);
    expect(scan.detections.first.polygon.length, greaterThan(2));
  });
}
