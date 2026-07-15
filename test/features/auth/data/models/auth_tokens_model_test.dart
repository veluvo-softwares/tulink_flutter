import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/auth/data/models/auth_tokens_model.dart';

void main() {
  test('toString never exposes authentication token contents', () {
    const model = AuthTokensModel(
      idToken: 'secret-id-token',
      refreshToken: 'secret-refresh-token',
      expiresIn: 3600,
    );

    final description = model.toString();

    expect(description, contains('idToken: [REDACTED]'));
    expect(description, contains('refreshToken: [REDACTED]'));
    expect(description, isNot(contains('secret-id-token')));
    expect(description, isNot(contains('secret-refresh-token')));
  });
}
