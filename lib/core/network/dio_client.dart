import 'package:dio/dio.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import '../auth/token_manager.dart';
import '../config/app_config.dart';
import '../errors/failure.dart';
import 'request_log_filter.dart';

/// A singleton Dio client with centralized configuration
class DioClient {
  DioClient._internal();

  static final DioClient _instance = DioClient._internal();
  factory DioClient() => _instance;

  late Dio _dio;
  final TokenManager _tokenManager = TokenManager();

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

  /// Authentication interceptor. Queued so that simultaneous 401s don't race
  /// to refresh — only the first triggers a refresh, the rest wait for it
  /// via the Completer guard in TokenManager and retry with the new token.
  Interceptor _createAuthInterceptor() {
    return QueuedInterceptorsWrapper(
      onRequest: (options, handler) async {
        try {
          final token = await _tokenManager.getValidAuthToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        } on TokenFailure catch (failure) {
          if (failure == TokenFailure.accessTokenExpired) {
            try {
              final fresh = await _tokenManager.refreshAuthToken();
              options.headers['Authorization'] = 'Bearer $fresh';
              handler.next(options);
              return;
            } on TokenFailure catch (refreshFailure) {
              // Only a terminal (requiresReauth) failure rejects as an auth
              // error; a transient one fails as a network error so the session
              // — and the stored tokens — survive.
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: refreshFailure.requiresReauth
                      ? DioExceptionType.badResponse
                      : DioExceptionType.connectionError,
                  error: refreshFailure.requiresReauth
                      ? AuthFailure.refreshTokenExpired
                      : NetworkFailure.connectionError,
                ),
              );
              return;
            }
          }
          handler.next(options);
        }
      },
      onError: (error, handler) async {
        final status = error.response?.statusCode;
        if (status != 401) {
          handler.next(error);
          return;
        }

        // Loop guard: if this request was already retried after a refresh and
        // STILL 401s, the session is genuinely dead — clear and log out.
        final alreadyRetried =
            error.requestOptions.extra['__authRetried'] == true;
        if (alreadyRetried) {
          await _tokenManager.clearAllTokens();
          _tokenManager.onAuthLost?.call();
          handler.reject(
            DioException(
              requestOptions: error.requestOptions,
              response: error.response,
              type: DioExceptionType.badResponse,
              error: AuthFailure.tokenInvalid,
            ),
          );
          return;
        }

        // Attempt ONE refresh on ANY 401 — not only code == 'TOKEN_EXPIRED'.
        // The backend also returns TOKEN_REVOKED / AUTH_FAILED (and a per-request
        // getUser() can fail transiently), so gating refresh on a single code
        // caused spurious mid-journey logouts. Refresh-then-retry recovers every
        // recoverable case; we only log out if the refresh itself fails or the
        // retried request (marked __authRetried) 401s again via the guard above.
        try {
          final fresh = await _tokenManager.refreshAuthToken();
          final retryOptions = error.requestOptions;
          retryOptions.headers['Authorization'] = 'Bearer $fresh';
          retryOptions.extra['__authRetried'] = true;
          final response = await _dio.fetch<dynamic>(retryOptions);
          handler.resolve(response);
          return;
        } on TokenFailure catch (failure) {
          if (!failure.requiresReauth) {
            // Transient refresh failure (offline, timeout, or a 5xx/503 from the
            // refresh endpoint). The session is still valid — do NOT clear tokens
            // or log out. Fail only THIS request; the next attempt or a reconnect
            // recovers. This is the fix for spurious offline / mid-journey logouts.
            handler.reject(
              DioException(
                requestOptions: error.requestOptions,
                response: error.response,
                type: DioExceptionType.connectionError,
                error: NetworkFailure.connectionError,
              ),
            );
            return;
          }
          // Terminal: the refresh token is genuinely dead — end the session.
          await _tokenManager.clearAllTokens();
          _tokenManager.onAuthLost?.call();
          handler.reject(
            DioException(
              requestOptions: error.requestOptions,
              response: error.response,
              type: DioExceptionType.badResponse,
              error: AuthFailure.refreshTokenExpired,
            ),
          );
          return;
        }
      },
    );
  }

  /// Creates a retry interceptor for failed requests
  Interceptor _createRetryInterceptor() {
    return InterceptorsWrapper(
      onError: (error, handler) async {
        final shouldRetry = _shouldRetryRequest(error);

        // Per-request retry counter stored in requestOptions.extra — a shared
        // instance field raced across concurrent requests (A3-6), causing one
        // request's success to reset another's counter mid-cycle.
        final attempts =
            (error.requestOptions.extra['__retryCount'] as int?) ?? 0;

        if (shouldRetry && attempts < AppConfig.maxRetryAttempts) {
          final next = attempts + 1;
          error.requestOptions.extra['__retryCount'] = next;

          // Wait before retrying (exponential backoff)
          final delay = Duration(seconds: next * 2);
          await Future<void>.delayed(delay);

          try {
            print('🔄 Retrying request (attempt $next)...');
            final response = await _dio.fetch<dynamic>(error.requestOptions);
            handler.resolve(response);
            return;
          } catch (_) {
            // Fall through to propagate the error; the incremented per-request
            // count in extra caps further retries on the next pass.
          }
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
      filter: shouldLogRequest,
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

  /// True if a (non-expired) refresh token is stored — i.e. an expired access
  /// token is still recoverable without forcing the user to log in again.
  Future<bool> hasRefreshToken() async {
    return _tokenManager.hasValidRefreshToken();
  }

  /// Exchange the stored refresh token for a fresh ID token. Returns the new
  /// token, or null if there was nothing to refresh / the refresh failed (in
  /// which case TokenManager has already cleared tokens and fired onAuthLost).
  Future<String?> tryRefreshToken() async {
    try {
      return await _tokenManager.refreshAuthToken();
    } catch (_) {
      return null;
    }
  }

  /// Get token metadata for debugging
  Future<Map<String, dynamic>?> getTokenMetadata() async {
    return await _tokenManager.getTokenMetadata();
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
    await _tokenManager.refreshAuthToken();
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