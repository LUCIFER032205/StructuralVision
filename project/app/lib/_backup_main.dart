import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'screens/login_screen.dart';
import 'screens/camera_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.load();
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
  );
  runApp(const ProviderScope(child: App()));
}

final authStateProvider = StreamProvider<AuthState>(
    (ref) => Supabase.instance.client.auth.onAuthStateChange);

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(authStateProvider); // rebuild on login/logout
    final signedIn = Supabase.instance.client.auth.currentSession != null;
    return MaterialApp(
      title: 'Structural Vision AR',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: signedIn ? const CameraScreen() : const LoginScreen(),
    );
  }
}
