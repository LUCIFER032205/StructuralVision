import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';

enum PreviewMode { room, site }

class BuildingType {
  final String id, name, footprint;
  final String uri;
  final bool isCustom;
  final double sizeM;
  final int storeys;

  const BuildingType({
    required this.id,
    required this.name,
    required this.uri,
    required this.sizeM,
    this.footprint = '',
    this.storeys = 0,
    this.isCustom = false,
  });

  /// Smallest room-mode size that still reads as a building: about 1:80,
  /// so a storey is >= ~4 cm. A 24 m block at 20 cm (1:120) was just a box.
  double get roomMinM => BuildingCatalog.roomSteps
      .firstWhere((m) => m >= sizeM / 80, orElse: () => BuildingCatalog.roomSteps.last);

  /// Plugin scale = largest model dimension in metres (see site_preview_screen).
  double scaleFor(PreviewMode mode,
          {double roomSizeM = BuildingCatalog.roomDefaultM}) =>
      mode == PreviewMode.site ? sizeM : roomSizeM;
}

class BuildingCatalog {
  static const roomDefaultM = 0.4;
  static const roomSteps = [0.2, 0.4, 0.8, 1.5]; // tabletop .. coffee-table size

  static BuildingType get fallback => BuildingType(
        id: 'tower',
        name: 'Demo tower',
        uri: '${AppConfig.apiBase}/static/building.glb',
        sizeM: 20.0,
        storeys: 6,
        footprint: '6 x 6 m',
      );

  static List<BuildingType> parse(Map<String, dynamic> json, String baseUrl) {
    final out = <BuildingType>[];
    for (final raw in (json['buildings'] as List? ?? const [])) {
      final e = raw as Map<String, dynamic>;
      final file = e['file'], size = e['size_m'];
      if (file is! String || size is! num) continue; // one bad row can't blank the picker
      out.add(BuildingType(
        id: e['id'] as String? ?? file,
        name: e['name'] as String? ?? file,
        uri: '$baseUrl/static/buildings/$file',
        sizeM: size.toDouble(),
        storeys: (e['storeys'] as num?)?.toInt() ?? 0,
        footprint: e['footprint'] as String? ?? '',
      ));
    }
    return out;
  }

  /// Never throws: an unreachable backend still gets the legacy tower.
  static Future<List<BuildingType>> fetch() async {
    final base = AppConfig.apiBase;
    try {
      final r = await http
          .get(Uri.parse('$base/static/buildings/manifest.json'),
              headers: {'ngrok-skip-browser-warning': '1'})
          .timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final list = parse(jsonDecode(r.body) as Map<String, dynamic>, base);
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}
    return [fallback];
  }
}
