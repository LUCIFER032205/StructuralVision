import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:structural_vision_ar/building_catalog.dart';
import 'package:structural_vision_ar/screens/building_select_sheet.dart';

const _buildings = [
  BuildingType(
      id: 'house',
      name: 'Independent house (G+1)',
      uri: 'http://host/static/buildings/house.glb',
      sizeM: 10.6,
      storeys: 2,
      footprint: '10 x 8 m'),
  BuildingType(
      id: 'office',
      name: 'Office building (G+9)',
      uri: 'http://host/static/buildings/office.glb',
      sizeM: 32.4,
      storeys: 10,
      footprint: '20 x 20 m'),
];

/// Pumps a screen whose only button opens the sheet, and records what
/// `show` resolved to — that return value is the whole contract callers use.
Future<BuildingType?> _openAndTap(WidgetTester tester, String tapText) async {
  BuildingType? picked;
  var returned = false;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: ElevatedButton(
          onPressed: () async {
            picked = await BuildingSelectSheet.show(context,
                buildings: _buildings, selectedId: 'office');
            returned = true;
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(tapText));
  await tester.pumpAndSettle();
  expect(returned, true, reason: 'show() should have resolved');
  return picked;
}

void main() {
  testWidgets('lists every building with its size, and ticks the current one',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => BuildingSelectSheet.show(context,
                buildings: _buildings, selectedId: 'office'),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Independent house (G+1)'), findsOneWidget);
    expect(find.text('Office building (G+9)'), findsOneWidget);
    expect(find.textContaining('10 x 8 m'), findsOneWidget);
    expect(find.textContaining('32 m'), findsOneWidget); // office, rounded
    expect(find.byIcon(Icons.check_rounded), findsOneWidget); // only the current
  });

  testWidgets('tapping a building returns it', (tester) async {
    final picked = await _openAndTap(tester, 'Independent house (G+1)');
    expect(picked?.id, 'house');
  });

  testWidgets('dismissing without picking returns null', (tester) async {
    BuildingType? picked;
    var returned = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              picked = await BuildingSelectSheet.show(context,
                  buildings: _buildings);
              returned = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10)); // barrier, above the sheet
    await tester.pumpAndSettle();

    expect(returned, true);
    expect(picked, isNull);
  });
}
