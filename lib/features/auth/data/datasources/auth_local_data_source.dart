import 'package:hive/hive.dart';

import '../../../../core/errors/failure.dart';
import '../models/user_model.dart';

/// Local data source for authentication
/// Handles caching of user data using Hive
abstract class AuthLocalDataSource {
  /// Cache user data
  Future<void> cacheUser(UserModel user);

  /// Get cached user data
  Future<UserModel?> getCachedUser();

  /// Clear cached user data
  Future<void> clearCachedUser();

  /// Check if user data is cached
  Future<bool> isUserCached();

  /// Cache authentication token
  Future<void> cacheToken(String token);

  /// Get cached authentication token
  Future<String?> getCachedToken();

  /// Clear cached token
  Future<void> clearCachedToken();
}

class AuthLocalDataSourceImpl implements AuthLocalDataSource {
  AuthLocalDataSourceImpl(this._authBox);

  final Box<dynamic> _authBox;

  static const String _userKey = 'cached_user';
  static const String _tokenKey = 'auth_token';

  @override
  Future<void> cacheUser(UserModel user) async {
    try {
      await _authBox.put(_userKey, user);
    } catch (e) {
      throw CacheFailure.write;
    }
  }

  @override
  Future<UserModel?> getCachedUser() async {
    try {
      final userData = _authBox.get(_userKey);
      if (userData != null && userData is UserModel) {
        return userData;
      }
      return null;
    } catch (e) {
      throw CacheFailure.read;
    }
  }

  @override
  Future<void> clearCachedUser() async {
    try {
      await _authBox.delete(_userKey);
    } catch (e) {
      throw CacheFailure.delete;
    }
  }

  @override
  Future<bool> isUserCached() async {
    try {
      return _authBox.containsKey(_userKey);
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> cacheToken(String token) async {
    try {
      await _authBox.put(_tokenKey, token);
    } catch (e) {
      throw CacheFailure.write;
    }
  }

  @override
  Future<String?> getCachedToken() async {
    try {
      final token = _authBox.get(_tokenKey);
      return token is String ? token : null;
    } catch (e) {
      throw CacheFailure.read;
    }
  }

  @override
  Future<void> clearCachedToken() async {
    try {
      await _authBox.delete(_tokenKey);
    } catch (e) {
      throw CacheFailure.delete;
    }
  }
}