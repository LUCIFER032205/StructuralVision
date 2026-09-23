import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../theme.dart';

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
    // Supabase reads a sign-up with no credentials as an ANONYMOUS sign-in and
    // answers "Anonymous sign-ins are disabled" — which tells the user nothing
    // about the empty fields in front of them. Catch it here instead.
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter an email and a password');
      return;
    }
    if (!email.contains('@')) {
      setState(() => _error = 'That email address looks incomplete');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters');
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

  /// Sign-up only signs you in when the project has email confirmation off.
  /// With it on, Supabase returns no session and the screen would just sit
  /// there, so say what happened.
  Future<void> _signUp(GoTrueClient auth) => _run(() async {
        final res = await auth.signUp(
            email: _email.text.trim(), password: _password.text);
        if (res.session == null && mounted) {
          setState(() => _notice =
              'Account created. Check ${_email.text.trim()} for the confirmation link, then sign in.');
        }
      });

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
                    if (_error != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.danger.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                color: AppColors.danger, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_error!,
                                  style: AppTextStyles.bodySm
                                      .copyWith(color: AppColors.danger)),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_notice != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.accent.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.mark_email_unread_outlined,
                                color: AppColors.accent, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_notice!,
                                  style: AppTextStyles.bodySm
                                      .copyWith(color: AppColors.accent)),
                            ),
                          ],
                        ),
                      ),
                    ],
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
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _signUp(auth),
                      child: const Text('Create account'),
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
