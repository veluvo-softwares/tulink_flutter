/// Storage keys for consistent data persistence across the app
/// Centralized location for all storage-related constants
class StorageKeys {
  StorageKeys._();

  // Secure Storage Keys (for sensitive data)
  static const String authToken = 'auth_token';
  static const String refreshToken = 'refresh_token';
  static const String biometricEnabled = 'biometric_enabled';
  static const String pinCode = 'pin_code';

  // Hive Box Names (for local caching)
  static const String authBox = 'auth_box';
  static const String userBox = 'user_box';
  static const String cacheBox = 'cache_box';
  static const String settingsBox = 'settings_box';
  static const String notificationsBox = 'notifications_box';
  static const String offlineRoutesBox = 'offline_routes_v1';
  static const String offlineSessionsBox = 'offline_sessions_v1';
  static const String offlineTileMetadataBox = 'offline_tile_metadata_v1';
  static const String journeyHistoryBox = 'journey_history_v1';
  static const String locationOutboxBox = 'location_outbox_v1';
  static const String offlineStorageCipherKey = 'offline_storage_cipher_key_v1';

  // SharedPreferences Keys (for user preferences)
  static const String themeMode = 'theme_mode';
  static const String languageCode = 'language_code';
  static const String onboardingCompleted = 'onboarding_completed';
  static const String notificationsEnabled = 'notifications_enabled';
  static const String analyticsEnabled = 'analytics_enabled';

  // Cache Keys with Prefixes
  static const String userProfilePrefix = 'user_profile_';
  static const String userPostsPrefix = 'user_posts_';
  static const String notificationsPrefix = 'notifications_';
  static const String offlineRoutePrefix = 'offline_route_';
  static const String offlineSessionPrefix = 'offline_session_';
  static const String journeyHistoryPrefix = 'journey_history_';
  static const String offlineTilePrefix = 'offline_tile_';

  // Helper methods to generate dynamic keys
  static String userProfile(String userId) => '$userProfilePrefix$userId';
  static String userPosts(String userId) => '$userPostsPrefix$userId';
  static String userNotifications(String userId) =>
      '$notificationsPrefix$userId';
}
