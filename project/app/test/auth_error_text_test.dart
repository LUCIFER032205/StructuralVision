import 'package:flutter_test/flutter_test.dart';
import 'package:structural_vision_ar/screens/login_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('server error on sign-up reads as an email problem, not raw JSON', () {
    final e = AuthRetryableFetchException(
        message: '{"code":500,"error_code":"unexpected_failure"}', statusCode: '500');
    expect(authErrorText(e, serverError: 'email'), 'email');
  });

  test('no network', () {
    final e = AuthRetryableFetchException(message: 'ClientException: Failed host lookup');
    expect(authErrorText(e), contains('internet'));
  });

  test('known codes map, unknown ones pass the message through', () {
    expect(authErrorText(const AuthApiException('x', code: 'invalid_credentials')),
        'Wrong email or password');
    expect(authErrorText(const AuthApiException('raw', code: 'something_new')), 'raw');
  });
}
