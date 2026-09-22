import 'package:flutter_test/flutter_test.dart';
import 'package:structural_vision_ar/building_catalog.dart';

void main() {
  const base = 'http://host:8000';
  final json = {
    'buildings': [
      {'id': 'house', 'name': 'Independent house (G+1)', 'file': 'house.glb',
       'size_m': 10.3, 'storeys': 2, 'footprint': '10 x 8 m'},
      {'id': 'office', 'name': 'Office building (G+9)', 'file': 'office.glb',
       'size_m': 32.0, 'storeys': 10, 'footprint': '20 x 20 m'},
    ]
  };

  test('parse builds full model URLs under /static/buildings/', () {
    final list = BuildingCatalog.parse(json, base);
    expect(list.map((b) => b.id), ['house', 'office']);
    expect(list.first.uri, '$base/static/buildings/house.glb');
    expect(list.first.isCustom, false);
  });

  test('site mode is true size, room mode is tabletop size', () {
    final office = BuildingCatalog.parse(json, base)[1];
    expect(office.scaleFor(PreviewMode.site), 32.0);
    expect(office.scaleFor(PreviewMode.room), BuildingCatalog.roomDefaultM);
    expect(office.scaleFor(PreviewMode.room, roomSizeM: 0.8), 0.8);
  });

  test('parse skips malformed entries instead of failing the whole list', () {
    final list = BuildingCatalog.parse({
      'buildings': [
        {'id': 'bad'},                       // no file / size
        json['buildings']![0],
      ]
    }, base);
    expect(list.single.id, 'house');
  });

  test('fallback is the legacy tower so the screen always has something', () {
    expect(BuildingCatalog.fallback.uri, endsWith('/static/building.glb'));
    expect(BuildingCatalog.fallback.sizeM, 20.0);
  });
}
