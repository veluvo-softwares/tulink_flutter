import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import '../config/app_config.dart';
import '../constants/storage_keys.dart';
import '../auth/token_manager.dart';
import '../errors/failure.dart';
import 'api_routes.dart';

/// A singleton Dio client with centralized configuration
class DioClient {
  DioClient._internal();
  
  static final DioClient _instance = DioClient._internal();
  factory DioClient() => _instance;

  late Dio _dio;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final TokenManager _tokenManager = TokenManager();
  bool _isRefreshing = false;
  int _retryCount = 0;

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
          'User-Agent': '${AppConfig.appName}/${AppConfig.appVersion}',
        },
      ),
    );

    // Add interceptors in order of execution
    _dio.interceptors.addAll([
      _createAuthInterceptor(),
      _createRetryInterceptor(),
      _createLoggingInterceptor(),
    ]);

    // Validate and cleanup tokens on initialization
    _tokenManager.validateAndCleanupTokens().catchError((_) {
      // Silently handle cleanup errors
    });
  }

  /// Creates the authentication interceptor with enhanced token management
  Interceptor _createAuthInterceptor() {
    return InterceptorsWrapper(
      onRequest: (options, handler) async {
        try {
          // Check if token will expire soon and refresh if needed
          if (await _tokenManager.willTokenExpireSoon()) {
            final refreshToken = await _tokenManager.getValidRefreshToken();
            if (refreshToken != null && !_isRefreshing) {
              try {
                await _performTokenRefresh();
              } catch (e) {
                // If preemptive refresh fails, continue with current token
                print('🔄 Preemptive token refresh failed: $e');
              }
            }
          }

          // Add auth token to requests if available
          final token = await _tokenManager.getValidAuthToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          
          handler.next(options);
        } catch (e) {
          if (e is TokenFailure && e.requiresReauth) {
            // Clear all tokens and let the request proceed without auth
            await _tokenManager.clearAllTokens();
          }
          handler.next(options);
        }
      },
      onError: (error, handler) async {
        // Handle token expiration (401 Unauthorized)
        if (error.response?.statusCode == 401 && !_isRefreshing) {
          try {
            final refreshToken = await _tokenManager.getValidRefreshToken();
            
            // Only attempt refresh if we have a refresh token and aren't already refreshing
            if (refreshToken != null && refreshToken.isNotEmpty) {
              _isRefreshing = true;
              
              try {
                // Attempt to refresh the token
                await _performTokenRefresh();
                
                // Retry the original request with new token
                final newToken = await _tokenManager.getValidAuthToken();
                if (newToken != null) {
                  final requestOptions = error.requestOptions;
                  requestOptions.headers['Authorization'] = 'Bearer $newToken';
                  
                  final response = await _dio.fetch(requestOptions);
                  handler.resolve(response);
                  return;
                }
              } catch (refreshError) {
                print('🔄 Token refresh failed: $refreshError');
                // Refresh failed, clear tokens and logout user
                await _tokenManager.clearAllTokens();
                
                // Convert to auth failure and pass through
                final authFailure = refreshError is TokenFailure 
                    ? AuthFailure.refreshTokenExpired
                    : AuthFailure.tokenExpired;
                
                // Create a new DioException with auth failure details
                final authError = DioException(
                  requestOptions: error.requestOptions,
                  response: error.response,
                  type: DioExceptionType.badResponse,
                  error: authFailure.message,
                );
                
                handler.reject(authError);
                return;
              } finally {
                _isRefreshing = false;
              }
            } else {
              // No refresh token, clear tokens and logout
              await _tokenManager.clearAllTokens();
            }
          } catch (e) {
            print('🔄 Auth error handling failed: $e');
          }
        }
        
        handler.next(error);
      },
    );
  }

  /// Creates a retry interceptor for failed requests
  Interceptor _createRetryInterceptor() {
    return InterceptorsWrapper(
      onError: (error, handler) async {
        final shouldRetry = _shouldRetryRequest(error);
        
        if (shouldRetry && _retryCount < AppConfig.maxRetryAttempts) {
          _retryCount++;
          
          // Wait before retrying (exponential backoff)
          final delay = Duration(seconds: _retryCount * 2);
          await Future.delayed(delay);
          
          try {
            print('🔄 Retrying request (attempt $_retryCount)...');
            final response = await _dio.fetch(error.requestOptions);
            _retryCount = 0; // Reset retry count on success
            handler.resolve(response);
            return;
          } catch (retryError) {
            if (_retryCount >= AppConfig.maxRetryAttempts) {
              _retryCount = 0;
              print('🔄 Max retry attempts reached');
            }
          }
        }
        
        _retryCount = 0; // Reset retry count
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

  /// Store authentication token securely using TokenManager
  Future<void> saveAuthToken(String token) async {
    await _tokenManager.saveAuthToken(token);
  }

  /// Store refresh token securely using TokenManager
  Future<void> saveRefreshToken(String refreshToken) async {
    await _tokenManager.saveRefreshToken(refreshToken);
  }

  /// Get stored authentication token
  Future<String?> getAuthToken() async {
    try {
      return await _tokenManager.getValidAuthToken();
    } catch (e) {
      return null;
    }
  }

  /// Get stored refresh token
  Future<String?> getRefreshToken() async {
    try {
      return await _tokenManager.getValidRefreshToken();
    } catch (e) {
      return null;
    }
  }

  /// Clear all stored tokens
  Future<void> clearTokens() async {
    await _tokenManager.clearAllTokens();
  }

  /// Check if user is authenticated
  Future<bool> isAuthenticated() async {
    return await _tokenManager.hasValidAuthToken();
  }

  /// Get token metadata for debugging
  Future<Map<String, dynamic>?> getTokenMetadata() async {
    return await _tokenManager.getTokenMetadata();
  }

  /// Refresh authentication token using refresh token
  Future<void> _performTokenRefresh() async {
    try {
      final refreshToken = await _tokenManager.getValidRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        throw TokenFailure.tokenMissing.copyWith(
          details: 'No valid refresh token available for refresh operation.',
        );
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
        
        // Handle both direct token response and wrapped response
        Map<String, dynamic> tokens;
        if (responseData.containsKey('data')) {
          tokens = responseData['data']['tokens'] as Map<String, dynamic>;
        } else if (responseData.containsKey('tokens')) {
          tokens = responseData['tokens'] as Map<String, dynamic>;
        } else {
          throw TokenFailure(
            message: 'Invalid refresh response format',
            details: 'Token refresh response does not contain expected token data.',
            timestamp: DateTime.now(),
          );
        }
        
        final newToken = tokens['idToken'] as String?;
        final newRefreshToken = tokens['refreshToken'] as String?;
        
        if (newToken == null) {
          throw TokenFailure(
            message: 'Invalid token refresh response',
            details: 'No access token received in refresh response.',
            timestamp: DateTime.now(),
          );
        }
        
        // Save new tokens
        await _tokenManager.saveAuthToken(newToken);
        if (newRefreshToken != null) {
          await _tokenManager.saveRefreshToken(newRefreshToken);
        }
        
        print('✅ Token refreshed successfully');
      } else {
        throw TokenFailure(
          message: 'Token refresh failed',
          details: 'Server responded with status ${response.statusCode}',
          timestamp: DateTime.now(),
        );
      }
    } catch (e) {
      if (e is DioException) {
        if (e.response?.statusCode == 401) {
          throw TokenFailure.refreshTokenExpired;
        }
        throw TokenFailure(
          message: 'Token refresh network error',
          details: 'Failed to connect to server for token refresh.',
          timestamp: DateTime.now(),
        );
      }
      
      if (e is TokenFailure) rethrow;
      
      throw TokenFailure(
        message: 'Token refresh failed',
        details: 'An unexpected error occurred during token refresh: ${e.toString()}',
        timestamp: DateTime.now(),
      );
    }
  }

  /// Determine if a request should be retried
  bool _shouldRetryRequest(DioException error) {
    // Don't retry auth errors or client errors
    if (error.response?.statusCode == 401 || 
        error.response?.statusCode == 403 ||
        (error.response?.statusCode ?? 0) >= 400 && 
        (error.response?.statusCode ?? 0) < 500) {
      return false;
    }

    // Retry on network errors, timeouts, and server errors
    return error.type == DioExceptionType.connectionTimeout ||
           error.type == DioExceptionType.receiveTimeout ||
           error.type == DioExceptionType.connectionError ||
           (error.response?.statusCode ?? 0) >= 500;
  }

  /// Force refresh token for testing purposes
  Future<void> forceTokenRefresh() async {
    if (_isRefreshing) return;
    
    _isRefreshing = true;
    try {
      await _performTokenRefresh();
    } finally {
      _isRefreshing = false;
    }
  }

  /// Check if token will expire soon
  Future<bool> willTokenExpireSoon() async {
    return await _tokenManager.willTokenExpireSoon();
  }

  /// Get time until token expires
  Future<Duration?> getTimeUntilTokenExpiry() async {
    return await _tokenManager.getTimeUntilTokenExpiry();
  }
}