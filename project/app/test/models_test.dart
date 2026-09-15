import 'package:flutter_test/flutter_test.dart';

import 'package:structural_vision_ar/models.dart';

void main() {
  test('ScanResult parses backend response', () {
    final scan = ScanResult.fromJson({
      'id': 'abc',
      'status': 'done',
      'component_type': 'wall',
      'risk_level': 'MEDIUM',
      'crack_count': 1,
      'crack_area_ratio': 0.02,
      'detections': [
        {
          'bbox': [1, 2, 3, 4],
          'polygon': [
            [0, 0],
            [10, 0],
            [10, 10],
          ],
          'confidence': 0.8,
          'area_ratio': 0.02,
        }
      ],
    });
    expect(scan.isDone, true);
    expect(scan.componentType, 'wall');
    expect(scan.riskLevel, 'MEDIUM');
    expect(scan.detections.single.polygon.length, 3);
    expect(scan.isMeasured, false);
    expect(scan.gradeSummary, isNull);
  });

  test('ScanResult parses measured grade', () {
    ScanResult parse(Map<String, dynamic> extra) => ScanResult.fromJson(
        {'id': 'abc', 'status': 'done', 'risk_source': 'measured', ...extra});
    final rc = parse({
      'component_type': 'column',
      'risk_level': 'MEDIUM',
      'crack_width_mm': 0.5,
      'damage_standard': 'JBDPA',
      'damage_class': 'II',
      'damage_rating': 'Moderate',
      'residual_capacity_pct': 60.0,
    });
    expect(rc.isMeasured, true);
    expect(rc.gradeSummary, 'JBDPA class II · Moderate · 60% capacity');
    final brick = parse({
      'component_type': 'wall',
      'crack_width_mm': 10,
      'damage_standard': 'BRE251',
      'damage_class': '3',
      'damage_rating': 'Serviceability',
    });
    expect(brick.gradeSummary, 'BRE 251 cat. 3 · Serviceability');
  });
}
