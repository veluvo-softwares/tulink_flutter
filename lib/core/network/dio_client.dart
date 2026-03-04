import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import '../config/app_config.dart';
import '../constants/storage_keys.dart';
import 'api_routes.dart';

/// A singleton Dio client with centralized configuration
class DioClient {
  DioClient._internal();
  
  static final DioClient _instance = DioClient._internal();
  factory DioClient() => _instance;

  late Dio _dio;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  bool _isRefreshing = false;

  Dio get dio => _dio;

  /// Initialize the Dio client with interceptors
  void initialize() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: AppConfig.connectTimeout,
        receiveTimeout: AppConfig.receiveTimeout,
        sendTimeout: AppConfig.sendTimeout,
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
        final token = await _secureStorage.read(key: StorageKeys.authToken);
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        // Handle token expiration (401 Unauthorized)
        if (error.response?.statusCode == 401 && !_isRefreshing) {
          final refreshToken = await getRefreshToken();
          
          // Only attempt refresh if we have a refresh token and aren't already refreshing
          if (refreshToken != null && refreshToken.isNotEmpty) {
            _isRefreshing = true;
            
            try {
              // Attempt to refresh the token
              final newToken = await _refreshToken();
              
              if (newToken != null) {
                // Save new token and retry original request
                await saveAuthToken(newToken);
                
                // Update the failed request with new token and retry
                final requestOptions = error.requestOptions;
                requestOptions.headers['Authorization'] = 'Bearer $newToken';
                
                final response = await _dio.fetch(requestOptions);
                handler.resolve(response);
                return;
              }
            } catch (e) {
              // Refresh failed, clear tokens and logout user
              await clearTokens();
            } finally {
              _isRefreshing = false;
            }
          }
          
          // If no refresh token or refresh failed, clear tokens
          await clearTokens();
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
      enabled: AppConfig.enableDetailedLogging,
    );
  }

  /// Store authentication token securely
  Future<void> saveAuthToken(String token) async {
    await _secureStorage.write(key: StorageKeys.authToken, value: token);
  }

  /// Store refresh token securely
  Future<void> saveRefreshToken(String refreshToken) async {
    await _secureStorage.write(
      key: StorageKeys.refreshToken, 
      value: refreshToken,
    );
  }

  /// Get stored authentication token
  Future<String?> getAuthToken() async {
    return await _secureStorage.read(key: StorageKeys.authToken);
  }

  /// Get stored refresh token
  Future<String?> getRefreshToken() async {
    return await _secureStorage.read(key: StorageKeys.refreshToken);
  }

  /// Clear all stored tokens
  Future<void> clearTokens() async {
    await _secureStorage.delete(key: StorageKeys.authToken);
    await _secureStorage.delete(key: StorageKeys.refreshToken);
  }

  /// Check if user is authenticated
  Future<bool> isAuthenticated() async {
    final token = await getAuthToken();
    return token != null && token.isNotEmpty;
  }

  /// Refresh authentication token using refresh token
  Future<String?> _refreshToken() async {
    try {
      final refreshToken = await getRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        return null;
      }

      // Create a temporary Dio instance without interceptors to avoid recursion
      final tempDio = Dio(BaseOptions(baseUrl: AppConfig.baseUrl));
      
      // Add refresh token to request
      tempDio.options.headers['Authorization'] = 'Bearer $refreshToken';
      
      final response = await tempDio.post<Map<String, dynamic>>(
        ApiRoutes.refreshToken,
      );
      
      if (response.statusCode == 200 && response.data != null) {
        final responseData = response.data!;
        final data = responseData['data'] as Map<String, dynamic>;
        final tokens = data['tokens'] as Map<String, dynamic>;
        final newToken = tokens['idToken'] as String;
        final newRefreshToken = tokens['refreshToken'] as String?;
        
        // Save new refresh token if provided
        if (newRefreshToken != null) {
          await saveRefreshToken(newRefreshToken);
        }
        
        return newToken;
      }
    } catch (e) {
      // Refresh failed
      return null;
    }
    
    return null;
  }
}