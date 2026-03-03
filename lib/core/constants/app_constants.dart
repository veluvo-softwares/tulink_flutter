/// @deprecated Use AppConfig, StorageKeys, and ApiRoutes instead
/// This class will be removed in a future version
/// Migration:
/// - API config → AppConfig
/// - Storage keys → StorageKeys  
/// - Routes → ApiRoutes
@Deprecated('Use AppConfig, StorageKeys, and ApiRoutes instead')
class AppConstants {
  AppConstants._();

  // API Configuration - DEPRECATED: Use AppConfig.baseUrl
  @Deprecated('Use AppConfig.baseUrl instead')
  static const String baseUrl = 'http://localhost:3000/api/v1';
  
  @Deprecated('Use AppConfig.connectTimeout instead')
  static const Duration connectTimeout = Duration(seconds: 30);
  
  @Deprecated('Use AppConfig.receiveTimeout instead')
  static const Duration receiveTimeout = Duration(seconds: 30);
  
  @Deprecated('Use AppConfig.sendTimeout instead')
  static const Duration sendTimeout = Duration(seconds: 30);

  // Storage Keys - DEPRECATED: Use StorageKeys
  @Deprecated('Use StorageKeys.authToken instead')
  static const String tokenKey = 'auth_token';
  
  @Deprecated('Use StorageKeys.refreshToken instead')
  static const String refreshTokenKey = 'refresh_token';
  
  @Deprecated('Use StorageKeys.userDataKey instead')
  static const String userDataKey = 'user_data';

  // Hive Box Names - DEPRECATED: Use StorageKeys
  @Deprecated('Use StorageKeys.authBox instead')
  static const String authBoxName = 'auth_box';
  
  @Deprecated('Use StorageKeys.userBox instead')
  static const String userBoxName = 'user_box';
  
  @Deprecated('Use StorageKeys.cacheBox instead')
  static const String cacheBoxName = 'cache_box';

  // Theme Constants - DEPRECATED: Use StorageKeys
  @Deprecated('Use StorageKeys.themeMode instead')
  static const String themeKey = 'theme_mode';

  // Development Configuration - DEPRECATED: Use AppConfig
  @Deprecated('Use AppConfig.enableDetailedLogging instead')
  static const bool enableLogging = true;

  // Cache Duration - DEPRECATED: Use AppConfig
  @Deprecated('Use AppConfig.defaultCacheDuration instead')
  static const Duration cacheDuration = Duration(hours: 24);

  // App Information - DEPRECATED: Use AppConfig
  @Deprecated('Use AppConfig.appName instead')
  static const String appName = 'TuLink Flutter';
  
  @Deprecated('Use AppConfig.appVersion instead')
  static const String appVersion = '1.0.0';
}