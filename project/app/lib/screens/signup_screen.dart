import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import 'login_screen.dart' show AuthMessage, authErrorText, credentialError;

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _name     = TextEditingController();
  final _email    = TextEditingController();
  final _password = TextEditingController();
  final _confirm  = TextEditingController();
  bool _busy         = false;
  bool _showPassword = false;
  String? _error;

  Future<void> _submit() async {
    final name  = _name.text.trim();
    final email = _email.text.trim();
    final invalid = name.isEmpty
        ? 'Enter your name'
        : credentialError(email, _password.text) ??
            (_password.text != _confirm.text ? 'Passwords do not match' : null);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final res = await Supabase.instance.client.auth.signUp(
          email: email, password: _password.text, data: {'full_name': name});
      if (!mounted) return;
      // With email confirmation off the session arrives and main.dart has
      // already swapped home to the camera underneath this route; with it on
      // there is no session, so hand the email back to the sign-in screen.
      Navigator.of(context).pop(res.session == null ? email : null);
    } on AuthException catch (e) {
      // A 5xx on sign-up is almost always the confirmation email failing to send.
      setState(() => _error = authErrorText(e,
          serverError: "Couldn't send the confirmation email. "
              'Try again in a few minutes.'));
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _field(String label, IconData icon, {Widget? suffix}) =>
      InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.textMuted, size: 18),
        suffixIcon: suffix,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text('Create account', style: AppTextStyles.displayLg),
              const SizedBox(height: 6),
              Text('Save your scans and reports to your account',
                  style: AppTextStyles.bodySm),
              const SizedBox(height: 32),
              AppCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _name,
                      style: AppTextStyles.bodyMd,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                      decoration: _field('Full name', Icons.person_outline),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _email,
                      style: AppTextStyles.bodyMd,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      decoration: _field('Email', Icons.mail_outline),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _password,
                      style: AppTextStyles.bodyMd,
                      obscureText: !_showPassword,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: _field(
                        'Password (6+ characters)',
                        Icons.lock_outline,
                        suffix: IconButton(
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
                    const SizedBox(height: 14),
                    TextField(
                      controller: _confirm,
                      style: AppTextStyles.bodyMd,
                      obscureText: !_showPassword,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _busy ? null : _submit(),
                      decoration:
                          _field('Confirm password', Icons.lock_outline),
                    ),
                    const SizedBox(height: 8),
                    if (_error != null)
                      AuthMessage(_error!,
                          color: AppColors.danger, icon: Icons.error_outline),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.bg))
                          : const Text('Create account'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _busy ? null : () => Navigator.of(context).pop(),
                      child: const Text('Already have an account? Sign in'),
                    ),
                  ],
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
