import 'package:shared_preferences/shared_preferences.dart';

/// App-wide config.
///
/// Pass Supabase credentials at build time via --dart-define:
///   flutter run \
///     --dart-define=SUPABASE_URL=https://your-project.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=your-anon-key \
///     --dart-define=DEFAULT_API_BASE=http://192.168.x.x:8000
///
/// See README.md for full setup instructions.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// FastAPI backend base URL.
  /// For a physical phone use your PC's LAN IP; for the emulator use http://10.0.2.2:8000.
  /// Overridable at runtime from the login screen (gear icon) for demos.
  static const defaultApiBase = String.fromEnvironment(
    'DEFAULT_API_BASE',
    defaultValue: 'http://localhost:8000',
  );
  static String apiBase = defaultApiBase;

  static const _kApiBase = 'api_base_override';

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    apiBase = prefs.getString(_kApiBase) ?? defaultApiBase;
  }

  /// Empty/blank [url] resets to [defaultApiBase].
  static Future<void> setApiBase(String url) async {
    final prefs = await SharedPreferences.getInstance();
    url = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (url.isEmpty) {
      await prefs.remove(_kApiBase);
      apiBase = defaultApiBase;
    } else {
      await prefs.setString(_kApiBase, url);
      apiBase = url;
    }
  }
}
