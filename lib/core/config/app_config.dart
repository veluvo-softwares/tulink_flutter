import 'dart:io';

/// Application configuration and environment management
/// Handles environment-specific settings and feature flags
class AppConfig {
  AppConfig._();

  // Environment Detection
  static const String _environment = String.fromEnvironment(
    'FLUTTER_ENV',
    defaultValue: 'development',
  );

  static bool get isDevelopment => _environment == 'development';
  static bool get isStaging => _environment == 'staging';
  static bool get isProduction => _environment == 'production';

  // App Metadata
  static const String appName = 'TuLink Flutter';
  static const String appVersion = '1.0.0';
  static const String appPackage = 'com.tulink.flutter';

  // API Configuration by Environment
  static String get baseUrl {
    switch (_environment) {
      // case 'production':
      //   return 'https://api.tulink.com/v1';
      // case 'staging':
      //   return 'https://staging-api.tulink.com/v1';
      case 'development':
      default:
        return 'https://api.dev.tulink.xyz';
    }
  }



  // Network Configuration
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration sendTimeout = Duration(seconds: 30);

  // Feature Flags
  static bool get enableDetailedLogging => !isProduction;
  static bool get enableCrashReporting => isProduction;
  static bool get enableAnalytics => isProduction || isStaging;
  static bool get enableMockData => isDevelopment;

  // Cache Configuration
  static const Duration defaultCacheDuration = Duration(hours: 24);
  static const Duration shortCacheDuration = Duration(minutes: 15);
  static const Duration longCacheDuration = Duration(days: 7);

  // Pagination Defaults
  static const int defaultPageSize = 20;
  static const int maxPageSize = 100;

  // Security Configuration
  static const int tokenExpiryBufferMinutes = 5;
  static const int maxRetryAttempts = 3;

  // Storage Configuration
  static const String secureStoragePrefix = 'tulink_';
  
  // Debug Configuration
  static bool get showDebugBanner => isDevelopment;
  static bool get showPerformanceOverlay => isDevelopment;
}