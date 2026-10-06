import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../theme.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email    = TextEditingController();
  final _password = TextEditingController();
  bool _busy          = false;
  bool _showPassword  = false;
  String? _error;
  String? _notice;   // non-error feedback, e.g. "confirm your email"

  Future<void> _run(Future<void> Function() action) async {
    final invalid = credentialError(_email.text.trim(), _password.text);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    setState(() { _busy = true; _error = null; _notice = null; });
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

  /// SignupScreen pops with the new email only when Supabase wants the
  /// address confirmed first; a signed-in sign-up swaps home on its own.
  Future<void> _openSignUp() async {
    final email = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const SignupScreen()));
    if (email != null && mounted) {
      _email.text = email;
      setState(() {
        _error = null;
        _notice = 'Account created. Check $email for the confirmation link, then sign in.';
      });
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
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kCardRadius),
            side: const BorderSide(color: AppColors.border)),
        title: Text('Backend server', style: AppTextStyles.titleMd),
        content: TextField(
          controller: ctrl,
          style: AppTextStyles.bodyMd,
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 64),
              // ── Logo / header ────────────────────────────────────────────
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: AppColors.accent.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.radar,
                      color: AppColors.accent, size: 32),
                ),
              ),
              const SizedBox(height: 24),
              Text('StructuralVision',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.displayLg),
              const SizedBox(height: 6),
              Text('AI-powered structural analysis',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySm),
              const SizedBox(height: 48),
              // ── Form card ────────────────────────────────────────────────
              AppCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Sign in to continue',
                        style: AppTextStyles.titleMd),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _email,
                      style: AppTextStyles.bodyMd,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.mail_outline,
                            color: AppColors.textMuted, size: 18),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _password,
                      style: AppTextStyles.bodyMd,
                      obscureText: !_showPassword,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline,
                            color: AppColors.textMuted, size: 18),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _showPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: AppColors.textMuted,
                            size: 18,
                          ),
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_error != null)
                      AuthMessage(_error!, color: AppColors.danger,
                          icon: Icons.error_outline),
                    if (_notice != null)
                      AuthMessage(_notice!, color: AppColors.accent,
                          icon: Icons.mark_email_unread_outlined),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() => auth.signInWithPassword(
                              email: _email.text.trim(),
                              password: _password.text)),
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.bg))
                          : const Text('Sign in'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _busy ? null : _openSignUp,
                      child: const Text('New here? Create an account'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // ── Server config ─────────────────────────────────────────────
              Center(
                child: TextButton.icon(
                  onPressed: _editServer,
                  icon: const Icon(Icons.dns_outlined, size: 16),
                  label: const Text('Backend server'),
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.textMuted),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

/// Supabase reads a sign-up with no credentials as an ANONYMOUS sign-in and
/// answers "Anonymous sign-ins are disabled", which tells the user nothing about
/// the empty fields in front of them. Shared by sign-in and sign-up.
String? credentialError(String email, String password) {
  if (email.isEmpty || password.isEmpty) return 'Enter an email and a password';
  if (!email.contains('@')) return 'That email address looks incomplete';
  if (password.length < 6) return 'Password must be at least 6 characters';
  return null;
}

class AuthMessage extends StatelessWidget {
  const AuthMessage(this.text, {super.key, required this.color, required this.icon});

  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: AppTextStyles.bodySm.copyWith(color: color)),
            ),
          ],
        ),
      );
}
