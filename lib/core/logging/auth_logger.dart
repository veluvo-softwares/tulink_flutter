import 'dart:developer' as dev;
import '../config/app_config.dart';

/// Enhanced logging utility for authentication flows
class AuthLogger {
  AuthLogger._();
  
  static const String _logPrefix = '🔐 AUTH';
  
  /// Log authentication events
  static void logAuthEvent(String event, {
    String? userId,
    String? email,
    Map<String, dynamic>? metadata,
  }) {
    if (!AppConfig.enableDetailedLogging) return;
    
    final logData = <String, dynamic>{
      'event': event,
      'timestamp': DateTime.now().toIso8601String(),
      if (userId != null) 'userId': userId,
      if (email != null) 'email': _maskEmail(email),
      if (metadata != null) ...metadata,
    };
    
    _log('EVENT', logData.toString());
  }

  /// Log successful authentication
  static void logSignInSuccess({
    required String email,
    String? userId,
    bool hasRefreshToken = false,
  }) {
    logAuthEvent(
      'SIGN_IN_SUCCESS',
      email: email,
      userId: userId,
      metadata: {'hasRefreshToken': hasRefreshToken},
    );
  }

  /// Log authentication failure
  static void logSignInFailure({
    required String email,
    required String reason,
    int? statusCode,
  }) {
    logAuthEvent(
      'SIGN_IN_FAILURE',
      email: email,
      metadata: {
        'reason': reason,
        if (statusCode != null) 'statusCode': statusCode,
      },
    );
  }

  /// Log sign up events
  static void logSignUpSuccess({
    required String email,
    String? userId,
  }) {
    logAuthEvent(
      'SIGN_UP_SUCCESS',
      email: email,
      userId: userId,
    );
  }

  /// Log sign up failure
  static void logSignUpFailure({
    required String email,
    required String reason,
    int? statusCode,
  }) {
    logAuthEvent(
      'SIGN_UP_FAILURE',
      email: email,
      metadata: {
        'reason': reason,
        if (statusCode != null) 'statusCode': statusCode,
      },
    );
  }

  /// Log sign out events
  static void logSignOut({
    String? userId,
    String? reason,
  }) {
    logAuthEvent(
      'SIGN_OUT',
      userId: userId,
      metadata: {
        if (reason != null) 'reason': reason,
      },
    );
  }

  /// Log token refresh events
  static void logTokenRefresh({
    required bool success,
    String? reason,
    Duration? timeToExpiry,
  }) {
    logAuthEvent(
      success ? 'TOKEN_REFRESH_SUCCESS' : 'TOKEN_REFRESH_FAILURE',
      metadata: {
        if (reason != null) 'reason': reason,
        if (timeToExpiry != null) 'timeToExpiry': timeToExpiry.toString(),
      },
    );
  }

  /// Log token validation events
  static void logTokenValidation({
    required String tokenType,
    required bool isValid,
    DateTime? expiresAt,
    String? reason,
  }) {
    logAuthEvent(
      'TOKEN_VALIDATION',
      metadata: {
        'tokenType': tokenType,
        'isValid': isValid,
        if (expiresAt != null) 'expiresAt': expiresAt.toIso8601String(),
        if (reason != null) 'reason': reason,
      },
    );
  }

  /// Log session management events
  static void logSessionEvent({
    required String event,
    Duration? duration,
    Map<String, dynamic>? metadata,
  }) {
    logAuthEvent(
      'SESSION_$event',
      metadata: {
        if (duration != null) 'duration': duration.toString(),
        if (metadata != null) ...metadata,
      },
    );
  }

  /// Log API calls for debugging
  static void logApiCall({
    required String method,
    required String endpoint,
    int? statusCode,
    Duration? duration,
    bool hasAuth = false,
  }) {
    if (!AppConfig.enableDetailedLogging) return;
    
    final logData = {
      'method': method,
      'endpoint': endpoint,
      'hasAuth': hasAuth,
      'timestamp': DateTime.now().toIso8601String(),
      if (statusCode != null) 'statusCode': statusCode,
      if (duration != null) 'duration': '${duration.inMilliseconds}ms',
    };
    
    _log('API_CALL', logData.toString());
  }

  /// Log errors with context
  static void logError({
    required String message,
    required String context,
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    if (!AppConfig.enableDetailedLogging) return;
    
    final logData = {
      'context': context,
      'message': message,
      'timestamp': DateTime.now().toIso8601String(),
      if (error != null) 'error': error.toString(),
      if (metadata != null) ...metadata,
    };
    
    _log('ERROR', logData.toString());
    
    if (stackTrace != null) {
      dev.log(
        stackTrace.toString(),
        name: '$_logPrefix ERROR_STACK',
        level: 1000,
      );
    }
  }

  /// Log validation errors
  static void logValidationError({
    required String field,
    required String error,
    String? value,
  }) {
    if (!AppConfig.enableDetailedLogging) return;
    
    logAuthEvent(
      'VALIDATION_ERROR',
      metadata: {
        'field': field,
        'error': error,
        if (value != null) 'value': _maskSensitiveData(field, value),
      },
    );
  }

  /// Log cache operations
  static void logCacheOperation({
    required String operation,
    required String key,
    required bool success,
    String? error,
  }) {
    if (!AppConfig.enableDetailedLogging) return;
    
    logAuthEvent(
      'CACHE_OPERATION',
      metadata: {
        'operation': operation,
        'key': key,
        'success': success,
        if (error != null) 'error': error,
      },
    );
  }

  /// Log performance metrics
  static void logPerformance({
    required String operation,
    required Duration duration,
    Map<String, dynamic>? metadata,
  }) {
    if (!AppConfig.enableDetailedLogging) return;
    
    logAuthEvent(
      'PERFORMANCE',
      metadata: {
        'operation': operation,
        'duration': '${duration.inMilliseconds}ms',
        if (metadata != null) ...metadata,
      },
    );
  }

  /// Log security events
  static void logSecurityEvent({
    required String event,
    String? userId,
    String? ipAddress,
    Map<String, dynamic>? metadata,
  }) {
    if (!AppConfig.enableDetailedLogging) return;
    
    logAuthEvent(
      'SECURITY_EVENT',
      userId: userId,
      metadata: {
        'securityEvent': event,
        if (ipAddress != null) 'ipAddress': ipAddress,
        if (metadata != null) ...metadata,
      },
    );
  }

  /// Create a debug session summary
  static Map<String, dynamic> createDebugSummary({
    required bool isAuthenticated,
    String? userId,
    DateTime? lastTokenRefresh,
    Duration? sessionDuration,
    int? apiCallCount,
    Map<String, dynamic>? tokenMetadata,
  }) {
    return {
      'debugSummary': {
        'timestamp': DateTime.now().toIso8601String(),
        'isAuthenticated': isAuthenticated,
        if (userId != null) 'userId': userId,
        if (lastTokenRefresh != null) 'lastTokenRefresh': lastTokenRefresh.toIso8601String(),
        if (sessionDuration != null) 'sessionDuration': sessionDuration.toString(),
        if (apiCallCount != null) 'apiCallCount': apiCallCount,
        if (tokenMetadata != null) 'tokenMetadata': tokenMetadata,
      },
    };
  }

  /// Internal logging method
  static void _log(String type, String message) {
    dev.log(
      message,
      name: '$_logPrefix $type',
      level: type == 'ERROR' ? 1000 : 800,
    );
  }

  /// Mask email for privacy
  static String _maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return email;
    
    final username = parts[0];
    final domain = parts[1];
    
    if (username.length <= 2) {
      return '${username[0]}***@$domain';
    } else {
      return '${username[0]}***${username[username.length - 1]}@$domain';
    }
  }

  /// Mask sensitive data based on field type
  static String _maskSensitiveData(String field, String value) {
    switch (field.toLowerCase()) {
      case 'password':
      case 'confirmpassword':
      case 'newpassword':
        return '***';
      case 'email':
        return _maskEmail(value);
      case 'token':
      case 'refreshtoken':
      case 'accesstoken':
        return value.length > 8 
            ? '${value.substring(0, 4)}***${value.substring(value.length - 4)}'
            : '***';
      default:
        return value;
    }
  }

  /// Enable debug mode logging
  static void enableDebugMode() {
    logAuthEvent('DEBUG_MODE_ENABLED');
  }

  /// Disable debug mode logging
  static void disableDebugMode() {
    logAuthEvent('DEBUG_MODE_DISABLED');
  }
}