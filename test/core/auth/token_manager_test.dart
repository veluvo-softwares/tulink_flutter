import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/core/auth/token_manager.dart';
import 'package:tulink_flutter/core/constants/storage_keys.dart';
import 'package:tulink_flutter/core/errors/failure.dart';

/// Secure storage that can be told to behave like a locked Keychain or an
/// unavailable Keystore, which is what the session-loss bug turned on.
class _FakeSecureStorage implements FlutterSecureStorage {
  _FakeSecureStorage({this.readThrows = false});

  /// When true, every read fails the way the platform fails when storage is
  /// unavailable — the value is still there, we simply cannot reach it.
  bool readThrows;
  final Map<String, String> values = {};
  final List<String> deletedKeys = [];

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (readThrows) {
      throw PlatformExceptionLike('storage unavailable');
    }
    return values[key];
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    deletedKeys.add(key);
    values.remove(key);
  }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    deletedKeys.addAll(values.keys);
    values.clear();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Stand-in for the platform channel error thrown when storage is locked.
class PlatformExceptionLike implements Exception {
  PlatformExceptionLike(this.message);
  final String message;
  @override
  String toString() => 'PlatformExceptionLike: $message';
}

String _tokenBlob(String token) => jsonEncode({
  'token': token,
  'savedAt': DateTime.now().toIso8601String(),
});

void main() {
  late TokenManager manager;
  late _FakeSecureStorage storage;

  setUp(() {
    manager = TokenManager();
    storage = _FakeSecureStorage();
    manager.secureStorage = storage;
  });

  group('unreadable storage is not a dead session', () {
    test('refresh token read failure is transient, not corruption', () async {
      storage.values[StorageKeys.refreshToken] = _tokenBlob('refresh-abc');
      storage.readThrows = true;

      await expectLater(
        manager.getValidRefreshToken(),
        throwsA(
          isA<TokenFailure>().having(
            (f) => f.requiresReauth,
            'requiresReauth',
            isFalse,
          ),
        ),
      );
    });

    test('auth token read failure is transient, not corruption', () async {
      storage.values[StorageKeys.authToken] = _tokenBlob('auth-abc');
      storage.readThrows = true;

      await expectLater(
        manager.getValidAuthToken(),
        throwsA(
          isA<TokenFailure>().having(
            (f) => f.requiresReauth,
            'requiresReauth',
            isFalse,
          ),
        ),
      );
    });

    test('hasValidRefreshToken rethrows rather than answering false', () async {
      // A bare `false` here reads as "no session" to isSignedIn, which is how
      // a locked screen became a logout.
      storage.values[StorageKeys.refreshToken] = _tokenBlob('refresh-abc');
      storage.readThrows = true;

      await expectLater(
        manager.hasValidRefreshToken(),
        throwsA(
          isA<TokenFailure>().having(
            (f) => f.requiresReauth,
            'requiresReauth',
            isFalse,
          ),
        ),
      );
    });

    test('validateAndCleanupTokens keeps tokens it could not read', () async {
      storage.values[StorageKeys.authToken] = _tokenBlob('auth-abc');
      storage.values[StorageKeys.refreshToken] = _tokenBlob('refresh-abc');
      storage.readThrows = true;

      await manager.validateAndCleanupTokens();

      expect(
        storage.deletedKeys,
        isEmpty,
        reason: 'unreadable storage must never trigger a wipe',
      );
      expect(storage.values, hasLength(2));
    });
  });

  group('genuinely bad data is still terminal', () {
    test('unparseable blob reports corruption', () async {
      storage.values[StorageKeys.refreshToken] = 'not-json-at-all';

      await expectLater(
        manager.getValidRefreshToken(),
        throwsA(
          isA<TokenFailure>().having(
            (f) => f.requiresReauth,
            'requiresReauth',
            isTrue,
          ),
        ),
      );
    });

    test('readable but empty storage returns null', () async {
      expect(await manager.getValidRefreshToken(), isNull);
      expect(await manager.hasValidRefreshToken(), isFalse);
    });

    test('a stored token is returned intact', () async {
      storage.values[StorageKeys.refreshToken] = _tokenBlob('refresh-abc');

      expect(await manager.getValidRefreshToken(), 'refresh-abc');
      expect(await manager.hasValidRefreshToken(), isTrue);
    });
  });
}
