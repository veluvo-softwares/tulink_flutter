import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import '../constants/app_constants.dart';

/// A singleton Dio client with centralized configuration
class DioClient {
  DioClient._internal();
  
  static final DioClient _instance = DioClient._internal();
  factory DioClient() => _instance;

  late Dio _dio;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  Dio get dio => _dio;

  /// Initialize the Dio client with interceptors
  void initialize() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.baseUrl,
        connectTimeout: AppConstants.connectTimeout,
        receiveTimeout: AppConstants.receiveTimeout,
        sendTimeout: AppConstants.sendTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // Add interceptors in order of execution
    _dio.interceptors.addAll([
      _createAuthInterceptor(),
      _createLoggingInterceptor(),
    ]);
  }

  /// Creates the authentication interceptor
  Interceptor _createAuthInterceptor() {
    return InterceptorsWrapper(
      onRequest: (options, handler) async {
        // Add auth token to requests if available
        final token = await _secureStorage.read(key: AppConstants.tokenKey);
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        // Handle token expiration (401 Unauthorized)
        if (error.response?.statusCode == 401) {
          // Clear stored token
          await _secureStorage.delete(key: AppConstants.tokenKey);
          await _secureStorage.delete(key: AppConstants.refreshTokenKey);
          
          // You can add automatic token refresh logic here
          // For now, we'll just pass the error along
        }
        handler.next(error);
      },
    );
  }

  /// Creates the logging interceptor for development
  Interceptor _createLoggingInterceptor() {
    return PrettyDioLogger(
      requestHeader: true,
      requestBody: true,
      responseHeader: false,
      responseBody: true,
      error: true,
      compact: true,
      maxWidth: 90,
      enabled: AppConstants.enableLogging,
    );
  }

  /// Store authentication token securely
  Future<void> saveAuthToken(String token) async {
    await _secureStorage.write(key: AppConstants.tokenKey, value: token);
  }

  /// Store refresh token securely
  Future<void> saveRefreshToken(String refreshToken) async {
    await _secureStorage.write(
      key: AppConstants.refreshTokenKey, 
      value: refreshToken,
    );
  }

  /// Get stored authentication token
  Future<String?> getAuthToken() async {
    return await _secureStorage.read(key: AppConstants.tokenKey);
  }

  /// Get stored refresh token
  Future<String?> getRefreshToken() async {
    return await _secureStorage.read(key: AppConstants.refreshTokenKey);
  }

  /// Clear all stored tokens
  Future<void> clearTokens() async {
    await _secureStorage.delete(key: AppConstants.tokenKey);
    await _secureStorage.delete(key: AppConstants.refreshTokenKey);
  }

  /// Check if user is authenticated
  Future<bool> isAuthenticated() async {
    final token = await getAuthToken();
    return token != null && token.isNotEmpty;
  }
}