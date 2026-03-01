/// Application-wide constants
class AppConstants {
  AppConstants._();

  // API Configuration
  static const String baseUrl = 'https://api.example.com/';
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration sendTimeout = Duration(seconds: 30);

  // Secure Storage Keys
  static const String tokenKey = 'auth_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String userDataKey = 'user_data';

  // Hive Box Names
  static const String authBoxName = 'auth_box';
  static const String userBoxName = 'user_box';
  static const String cacheBoxName = 'cache_box';

  // Theme Constants
  static const String themeKey = 'theme_mode';

  // Development Configuration
  static const bool enableLogging = true; // Set to false in production

  // Cache Duration
  static const Duration cacheDuration = Duration(hours: 24);

  // App Information
  static const String appName = 'TuLink Flutter';
  static const String appVersion = '1.0.0';
}