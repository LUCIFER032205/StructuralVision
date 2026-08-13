import 'package:flutter_test/flutter_test.dart';

import 'package:structural_vision_ar/models.dart';

void main() {
  test('ScanResult parses backend response', () {
    final scan = ScanResult.fromJson({
      'id': 'abc',
      'status': 'done',
      'component_type': 'wall',
      'component_confidence': 0.97,
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
  });
}
