import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../../core/config/app_config.dart';

/// Thrown when the user backs out of a native provider flow. The caller treats
/// this as a benign cancellation (no error toast), not a failure.
class SocialSignInCancelled implements Exception {
  const SocialSignInCancelled(this.provider);

  final String provider;

  @override
  String toString() => 'SocialSignInCancelled($provider)';
}

/// Isolates all native provider SDK contact so the data source stays a pure
/// mapping layer. Returns the provider OIDC token(s) that the backend exchanges
/// through Firebase `accounts:signInWithIdp`.
///
/// Coded against google_sign_in 7.x (GoogleSignIn.instance + authenticate())
/// and sign_in_with_apple 8.x.
class SocialAuthService {
  bool _googleInitialized = false;

  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    // serverClientId = the Firebase WEB client ID, so the SDK mints an id token
    // audience the backend's signInWithIdp exchange accepts.
    await GoogleSignIn.instance.initialize(
      serverClientId: AppConfig.googleServerClientId,
    );
    _googleInitialized = true;
  }

  /// Trigger the Google flow and return the OIDC id token (+ display name).
  Future<({String idToken, String? displayName})> google() async {
    print('🧭 SocialAuthService.google() starting');
    await _ensureGoogleInitialized();

    try {
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;

      if (idToken == null) {
        print('❌ Google sign-in returned no idToken');
        throw Exception('Google sign-in did not return an id token');
      }

      print('✅ Google sign-in obtained idToken (${idToken.length} chars)');
      return (idToken: idToken, displayName: account.displayName);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        print('⚠️ Google sign-in cancelled by user');
        throw const SocialSignInCancelled('google');
      }
      print('❌ GoogleSignInException ${e.code}: ${e.description}');
      rethrow;
    }
  }

  /// Trigger the Apple flow with a hashed nonce and return the identity token,
  /// the RAW nonce (the backend re-hashes it), and the assembled name.
  ///
  /// Apple supplies givenName/familyName ONLY on the first authorization, so we
  /// capture and forward the name here or it is gone on subsequent sign-ins.
  Future<({String idToken, String rawNonce, String? displayName})> apple() async {
    print('🧭 SocialAuthService.apple() starting');

    final rawNonce = _generateNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        print('❌ Apple sign-in returned no identityToken');
        throw Exception('Apple sign-in did not return an identity token');
      }

      final displayName = _assembleAppleName(
        credential.givenName,
        credential.familyName,
      );

      print('✅ Apple sign-in obtained identityToken (${idToken.length} chars)');
      return (idToken: idToken, rawNonce: rawNonce, displayName: displayName);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        print('⚠️ Apple sign-in cancelled by user');
        throw const SocialSignInCancelled('apple');
      }
      print('❌ SignInWithAppleAuthorizationException ${e.code}: ${e.message}');
      rethrow;
    }
  }

  String? _assembleAppleName(String? given, String? family) {
    final parts = [given, family]
        .where((p) => p != null && p.trim().isNotEmpty)
        .map((p) => p!.trim());
    if (parts.isEmpty) return null;
    return parts.join(' ');
  }

  /// Cryptographically random alphanumeric nonce string.
  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }
}
