// Dev-only entry point: opens the AR site preview directly, with no login,
// so the AR path can be exercised on an emulator.
//   flutter run -t lib/ar_harness.dart --dart-define=DEFAULT_API_BASE=http://10.0.2.2:8000
// Not part of the shipped app (main.dart is the real entry point).
import 'package:flutter/material.dart';

import 'building_catalog.dart';
import 'config.dart';
import 'theme.dart';
import 'screens/site_preview_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.load();
  final buildings = await BuildingCatalog.fetch();
  runApp(MaterialApp(
    theme: buildAppTheme(),
    debugShowCheckedModeBanner: false,
    home: SitePreviewScreen(buildings: buildings),
  ));
}
