import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:structural_vision_ar/models.dart';
import 'package:structural_vision_ar/screens/result_screen.dart';
import 'package:structural_vision_ar/theme.dart';

/// Renders the result screen at a budget-phone size (Vivo Y200 ≈ 393dp wide)
/// for each state. Any RenderFlex overflow throws and fails the test.
Future<Uint8List> _png(int w, int h) async {
  final rec = ui.PictureRecorder();
  Canvas(rec).drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = const Color(0xFF777777));
  final img = await rec.endRecording().toImage(w, h);
  return (await img.toByteData(format: ui.ImageByteFormat.png))!
      .buffer
      .asUint8List();
}

ScanResult _scan(Map<String, dynamic> extra) => ScanResult.fromJson({
      'id': 'abcdef12-0000',
      'status': 'done',
      'component_type': 'rc_wall',
      'risk_level': 'MEDIUM',
      'crack_count': 2,
      'crack_area_ratio': 0.03,
      'detections': [
        {'bbox': [10, 10, 300, 40], 'polygon': [[10, 10], [300, 20], [300, 40], [10, 30]], 'confidence': 0.95, 'area_ratio': 0.02},
        {'bbox': [50, 200, 400, 230], 'polygon': [[50, 200], [400, 210], [400, 230], [50, 220]], 'confidence': 0.55, 'area_ratio': 0.01, 'crack_type': 'paint'},
      ],
      ...extra,
    });

void main() {
  final states = {
    'preliminary': _scan({}),
    'measured': _scan({
      'risk_source': 'measured', 'crack_width_mm': 0.5, 'damage_standard': 'JBDPA',
      'damage_class': 'II', 'damage_rating': 'Moderate', 'residual_capacity_pct': 60.0,
    }),
    'no_cracks': _scan({'risk_level': 'LOW', 'crack_count': 0, 'crack_area_ratio': 0.0, 'detections': []}),
  };

  for (final e in states.entries) {
    testWidgets('result screen: ${e.key}', (tester) async {
      tester.view.physicalSize = const Size(393 * 3, 873 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final bytes = (await tester.runAsync(() => _png(640, 480)))!;
      await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          home: ResultScreen(result: e.value, imageBytes: bytes)));
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
      if (e.key == 'preliminary') {
        expect(find.textContaining('Measure crack'), findsOneWidget);
      } else {
        expect(find.textContaining('Measure crack'), findsNothing);
      }
      if (e.key == 'no_cracks') expect(find.text('No cracks detected'), findsOneWidget);
    });
  }
}
