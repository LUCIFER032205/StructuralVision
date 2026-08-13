import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editServer() async {
    final ctrl = TextEditingController(
        text: AppConfig.apiBase == AppConfig.defaultApiBase
            ? ''
            : AppConfig.apiBase);
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Backend server'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Server URL',
            hintText: 'https://purr-decline-paycheck.ngrok-free.dev',
            helperText: 'Leave empty for default',
          ),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (url != null) {
      await AppConfig.setApiBase(url);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Structural Vision AR'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Backend server',
            onPressed: _editServer,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            TextField(
              controller: _password,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(() => auth.signInWithPassword(
                      email: _email.text.trim(), password: _password.text)),
              child: const Text('Sign in'),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _run(() => auth.signUp(
                      email: _email.text.trim(), password: _password.text)),
              child: const Text('Create account'),
            ),
          ],
        ),
      ),
    );
  }
}
