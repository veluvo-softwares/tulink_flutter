import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/app_config.dart';
import '../constants/storage_keys.dart';
import '../errors/failure.dart';
import '../network/api_routes.dart';

/// Enhanced token manager with expiry validation and automatic refresh
class TokenManager {
  TokenManager._();
  
  static final TokenManager _instance = TokenManager._();
  factory TokenManager() => _instance;

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  /// In-flight refresh. A second caller arriving while the first is still
  /// awaiting the network response gets the same future — never two parallel
  /// POST /auth/refresh requests, which would race-rotate the refresh token
  /// and lock the user out.
  Completer<String>? _refreshCompleter;

  /// Hook fired when tokens are cleared due to an unrecoverable auth state
  /// (refresh failed, token revoked, etc.). AuthProvider wires this to its
  /// signOut flow so the UI doesn't stay on a "signed in" screen with no
  /// credentials.
  void Function()? onAuthLost;

  /// Store authentication token with metadata
  Future<void> saveAuthToken(String token) async {
    try {
      final tokenData = {
        'token': token,
        'savedAt': DateTime.now().toIso8601String(),
        'expiresAt': _calculateTokenExpiry(token),
      };
      
      await _secureStorage.write(
        key: StorageKeys.authToken,
        value: jsonEncode(tokenData),
      );
    } catch (e) {
      throw TokenFailure(
        message: 'Failed to save authentication token',
        details: 'Could not securely store the authentication token.',
        timestamp: DateTime.now(),
        tokenType: 'access',
      );
    }
  }

  /// Store refresh token with metadata
  Future<void> saveRefreshToken(String refreshToken) async {
    try {
      final tokenData = {
        'token': refreshToken,
        'savedAt': DateTime.now().toIso8601String(),
        'expiresAt': _calculateRefreshTokenExpiry(refreshToken),
      };
      
      await _secureStorage.write(
        key: StorageKeys.refreshToken,
        value: jsonEncode(tokenData),
      );
    } catch (e) {
      throw TokenFailure(
        message: 'Failed to save refresh token',
        details: 'Could not securely store the refresh token.',
        timestamp: DateTime.now(),
        tokenType: 'refresh',
      );
    }
  }

  /// Get authentication token if valid
  Future<String?> getValidAuthToken() async {
    try {
      final tokenDataStr = await _secureStorage.read(key: StorageKeys.authToken);
      if (tokenDataStr == null) return null;

      final tokenData = jsonDecode(tokenDataStr) as Map<String, dynamic>;
      final token = tokenData['token'] as String;
      final expiresAt = tokenData['expiresAt'] as String?;

      if (expiresAt != null && _isTokenExpired(expiresAt)) {
        // Token is expired, remove it
        await clearAuthToken();
        throw TokenFailure.accessTokenExpired;
      }

      return token;
    } catch (e) {
      if (e is TokenFailure) rethrow;
      throw TokenFailure.tokenCorrupted;
    }
  }

  /// Get refresh token if valid
  Future<String?> getValidRefreshToken() async {
    try {
      final tokenDataStr = await _secureStorage.read(key: StorageKeys.refreshToken);
      if (tokenDataStr == null) return null;

      final tokenData = jsonDecode(tokenDataStr) as Map<String, dynamic>;
      final token = tokenData['token'] as String;
      final expiresAt = tokenData['expiresAt'] as String?;

      if (expiresAt != null && _isTokenExpired(expiresAt)) {
        // Refresh token is expired, remove it
        await clearRefreshToken();
        throw TokenFailure.refreshTokenExpired;
      }

      return token;
    } catch (e) {
      if (e is TokenFailure) rethrow;
      throw TokenFailure.tokenCorrupted;
    }
  }

  /// Check if auth token exists and is valid
  Future<bool> hasValidAuthToken() async {
    try {
      final token = await getValidAuthToken();
      return token != null;
    } catch (e) {
      return false;
    }
  }

  /// Check if refresh token exists and is valid
  Future<bool> hasValidRefreshToken() async {
    try {
      final token = await getValidRefreshToken();
      return token != null;
    } catch (e) {
      return false;
    }
  }

  /// Check if token will expire soon (within buffer time)
  Future<bool> willTokenExpireSoon() async {
    try {
      final tokenDataStr = await _secureStorage.read(key: StorageKeys.authToken);
      if (tokenDataStr == null) return true;

      final tokenData = jsonDecode(tokenDataStr) as Map<String, dynamic>;
      final expiresAt = tokenData['expiresAt'] as String?;

      if (expiresAt == null) {
        // If we don't have expiry info, assume it might expire soon
        return true;
      }

      final expiryDate = DateTime.parse(expiresAt);
      final bufferTime = Duration(
        minutes: AppConfig.tokenExpiryBufferMinutes,
      );
      
      return DateTime.now().add(bufferTime).isAfter(expiryDate);
    } catch (e) {
      return true;
    }
  }

  /// Get time remaining until token expires
  Future<Duration?> getTimeUntilTokenExpiry() async {
    try {
      final tokenDataStr = await _secureStorage.read(key: StorageKeys.authToken);
      if (tokenDataStr == null) return null;

      final tokenData = jsonDecode(tokenDataStr) as Map<String, dynamic>;
      final expiresAt = tokenData['expiresAt'] as String?;

      if (expiresAt == null) return null;

      final expiryDate = DateTime.parse(expiresAt);
      final now = DateTime.now();
      
      if (now.isAfter(expiryDate)) return Duration.zero;
      
      return expiryDate.difference(now);
    } catch (e) {
      return null;
    }
  }

  /// Clear authentication token
  Future<void> clearAuthToken() async {
    try {
      await _secureStorage.delete(key: StorageKeys.authToken);
    } catch (e) {
      throw TokenFailure(
        message: 'Failed to clear authentication token',
        details: 'Could not remove the authentication token from storage.',
        timestamp: DateTime.now(),
      );
    }
  }

  /// Clear refresh token
  Future<void> clearRefreshToken() async {
    try {
      await _secureStorage.delete(key: StorageKeys.refreshToken);
    } catch (e) {
      throw TokenFailure(
        message: 'Failed to clear refresh token',
        details: 'Could not remove the refresh token from storage.',
        timestamp: DateTime.now(),
      );
    }
  }

  /// Clear all tokens
  Future<void> clearAllTokens() async {
    await clearAuthToken();
    await clearRefreshToken();
  }

  /// Exchange the stored refresh token for a fresh ID token.
  ///
  /// Concurrent callers share a single in-flight request via [_refreshCompleter].
  /// On any failure (network, non-200, bad shape, expired refresh token) all
  /// tokens are cleared and [onAuthLost] is fired so the app can navigate to
  /// login. The endpoint uses a bare Dio instance — going through DioClient
  /// here would re-enter the auth interceptor and deadlock.
  Future<String> refreshAuthToken() async {
    final inFlight = _refreshCompleter;
    if (inFlight != null) {
      return inFlight.future;
    }

    final completer = Completer<String>();
    _refreshCompleter = completer;

    try {
      final newToken = await _doRefresh();
      completer.complete(newToken);
      return newToken;
    } catch (e, st) {
      completer.completeError(e, st);
      rethrow;
    } finally {
      _refreshCompleter = null;
    }
  }

  Future<String> _doRefresh() async {
    String? refreshToken;
    try {
      refreshToken = await getValidRefreshToken();
    } on TokenFailure {
      refreshToken = null;
    }

    if (refreshToken == null || refreshToken.isEmpty) {
      await _failRefresh();
    }

    try {
      final bareDio = Dio(
        BaseOptions(
          baseUrl: AppConfig.baseUrl,
          connectTimeout: AppConfig.connectTimeout,
          receiveTimeout: AppConfig.receiveTimeout,
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
      );

      final response = await bareDio.post<Map<String, dynamic>>(
        ApiRoutes.refreshToken,
        data: {'refreshToken': refreshToken},
      );

      if (response.statusCode != 200 || response.data == null) {
        await _failRefresh();
      }

      final data = response.data!['data'];
      if (data is! Map<String, dynamic>) {
        await _failRefresh();
      }

      final newIdToken = data['idToken'];
      final newRefreshToken = data['refreshToken'];

      if (newIdToken is! String || newIdToken.isEmpty ||
          newRefreshToken is! String || newRefreshToken.isEmpty) {
        await _failRefresh();
      }

      await saveAuthToken(newIdToken);
      await saveRefreshToken(newRefreshToken);

      return newIdToken;
    } catch (e) {
      if (e is TokenFailure) rethrow;
      await _failRefresh();
    }
  }

  Future<Never> _failRefresh() async {
    await clearAllTokens();
    onAuthLost?.call();
    throw TokenFailure.refreshTokenExpired;
  }

  /// Get token metadata for debugging
  Future<Map<String, dynamic>?> getTokenMetadata() async {
    try {
      final authTokenStr = await _secureStorage.read(key: StorageKeys.authToken);
      final refreshTokenStr = await _secureStorage.read(key: StorageKeys.refreshToken);

      final metadata = <String, dynamic>{};

      if (authTokenStr != null) {
        final authTokenData = jsonDecode(authTokenStr) as Map<String, dynamic>;
        metadata['authToken'] = {
          'exists': true,
          'savedAt': authTokenData['savedAt'],
          'expiresAt': authTokenData['expiresAt'],
          'isExpired': authTokenData['expiresAt'] != null 
              ? _isTokenExpired(authTokenData['expiresAt'] as String)
              : false,
        };
      } else {
        metadata['authToken'] = {'exists': false};
      }

      if (refreshTokenStr != null) {
        final refreshTokenData = jsonDecode(refreshTokenStr) as Map<String, dynamic>;
        metadata['refreshToken'] = {
          'exists': true,
          'savedAt': refreshTokenData['savedAt'],
          'expiresAt': refreshTokenData['expiresAt'],
          'isExpired': refreshTokenData['expiresAt'] != null
              ? _isTokenExpired(refreshTokenData['expiresAt'] as String)
              : false,
        };
      } else {
        metadata['refreshToken'] = {'exists': false};
      }

      return metadata;
    } catch (e) {
      return null;
    }
  }

  /// Validate stored tokens and clean up expired ones
  Future<void> validateAndCleanupTokens() async {
    try {
      // Check and clean auth token
      final authTokenStr = await _secureStorage.read(key: StorageKeys.authToken);
      if (authTokenStr != null) {
        try {
          final authTokenData = jsonDecode(authTokenStr) as Map<String, dynamic>;
          final expiresAt = authTokenData['expiresAt'] as String?;
          
          if (expiresAt != null && _isTokenExpired(expiresAt)) {
            await clearAuthToken();
          }
        } catch (e) {
          // Token data is corrupted, clear it
          await clearAuthToken();
        }
      }

      // Check and clean refresh token
      final refreshTokenStr = await _secureStorage.read(key: StorageKeys.refreshToken);
      if (refreshTokenStr != null) {
        try {
          final refreshTokenData = jsonDecode(refreshTokenStr) as Map<String, dynamic>;
          final expiresAt = refreshTokenData['expiresAt'] as String?;
          
          if (expiresAt != null && _isTokenExpired(expiresAt)) {
            await clearRefreshToken();
          }
        } catch (e) {
          // Token data is corrupted, clear it
          await clearRefreshToken();
        }
      }
    } catch (e) {
      // If validation fails, clear all tokens for security
      await clearAllTokens();
    }
  }

  /// Calculate token expiry time (estimate based on JWT or default)
  String? _calculateTokenExpiry(String token) {
    try {
      // Try to decode JWT token to get actual expiry
      final parts = token.split('.');
      if (parts.length >= 2) {
        // Add padding if needed
        String payload = parts[1];
        while (payload.length % 4 != 0) {
          payload += '=';
        }
        
        final decoded = base64Decode(payload);
        final payloadJson = jsonDecode(utf8.decode(decoded)) as Map<String, dynamic>;
        
        if (payloadJson.containsKey('exp')) {
          final exp = payloadJson['exp'] as int;
          return DateTime.fromMillisecondsSinceEpoch(exp * 1000).toIso8601String();
        }
      }
    } catch (e) {
      // JWT parsing failed, fall back to estimate
    }

    // Default expiry time (1 hour from now)
    return DateTime.now().add(const Duration(hours: 1)).toIso8601String();
  }

  /// Calculate refresh token expiry (typically longer than access token)
  String? _calculateRefreshTokenExpiry(String refreshToken) {
    try {
      // Try to decode JWT refresh token
      final parts = refreshToken.split('.');
      if (parts.length >= 2) {
        String payload = parts[1];
        while (payload.length % 4 != 0) {
          payload += '=';
        }
        
        final decoded = base64Decode(payload);
        final payloadJson = jsonDecode(utf8.decode(decoded)) as Map<String, dynamic>;
        
        if (payloadJson.containsKey('exp')) {
          final exp = payloadJson['exp'] as int;
          return DateTime.fromMillisecondsSinceEpoch(exp * 1000).toIso8601String();
        }
      }
    } catch (e) {
      // JWT parsing failed, fall back to estimate
    }

    // Default refresh token expiry (7 days from now)
    return DateTime.now().add(const Duration(days: 7)).toIso8601String();
  }

  /// Check if a token is expired
  bool _isTokenExpired(String expiresAt) {
    try {
      final expiryDate = DateTime.parse(expiresAt);
      return DateTime.now().isAfter(expiryDate);
    } catch (e) {
      return true; // If we can't parse the date, assume it's expired
    }
  }
}