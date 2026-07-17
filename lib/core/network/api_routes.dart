/// API route definitions - pure path constants
/// Contains only endpoint paths without any configuration
/// Use with base URL from AppConfig to form complete URLs
class ApiRoutes {
  ApiRoutes._();

  // Authentication Routes
  static const String signIn = '/auth/login';
  static const String signUp = '/auth/register';
  static const String signOut = '/auth/logout';
  static const String refreshToken = '/auth/refresh';
  static const String currentUser = '/auth/profile';
  static const String forgotPassword = '/auth/forgot-password';
  static const String resetPassword = '/auth/reset-password';
  static const String verifyEmail = '/auth/verify-email';
  static const String sendEmailVerification = '/auth/send-email-verification';
  static const String socialSignIn = '/auth/social';
  static const String updateProfile = '/auth/profile';
  static const String deleteAccount = '/auth/account';
  static const String searchUser = '/auth/searchUser';

  // Journey Invite Routes
  static String journeyInvite(String journeyId) =>
      '/journeys/$journeyId/invite';
  static const String journeyInvitations = '/journeys/invitations';
  static String joinJourneyCode(String code) => '/journeys/join-code/$code';
  static String acceptInvitation(String journeyId) =>
      '/journeys/$journeyId/accept';

  // User Management Routes
  static const String users = '/users';
  static const String userSearch = '/users/search';
  static const String userPreferences = '/users/preferences';

  // Dynamic User Routes
  static String userById(String id) => '/users/$id';
  static String userFollowers(String id) => '/users/$id/followers';
  static String userFollowing(String id) => '/users/$id/following';

  // Content Routes

  static const String trending = '/posts/trending';
  static const String feed = '/feed';

  // Dynamic Content Routes
  static String postById(String id) => '/posts/$id';
  static String postComments(String postId) => '/posts/$postId/comments';
  static String postLikes(String postId) => '/posts/$postId/likes';
  static String commentById(String postId, String commentId) =>
      '/posts/$postId/comments/$commentId';

  // Media Routes
  static const String uploadImage = '/media/images';
  static const String uploadVideo = '/media/videos';
  static const String uploadDocument = '/media/documents';
  static String mediaById(String id) => '/media/$id';
  static String downloadMedia(String id) => '/media/$id/download';

  // Notification Routes
  static const String notifications = '/notifications';
  static const String fcmToken = '/notifications/fcm-token';
  static const String notificationSettings = '/notifications/settings';
  static String markNotificationRead(String id) => '/notifications/$id/read';
  static String markNotificationUnread(String id) =>
      '/notifications/$id/unread';

  // Search Routes
  static const String search = '/search';
  static const String searchUsers = '/search/users';
  static const String searchPosts = '/search/posts';
  static const String searchHashtags = '/search/hashtags';

  // Analytics Routes
  static const String analytics = '/analytics';
  static const String analyticsEvents = '/analytics/events';
  static const String analyticsUserStats = '/analytics/users/stats';
  static const String userAnalytics = '/analytics/user';
  static const String userJourneyHistory = '/analytics/user';

  // Dynamic Analytics Routes
  static String journeyAnalytics(String id) => '/analytics/journeys/$id';
  static String journeySummary(String id) => '/analytics/journeys/$id/summary';

  // Admin Routes (if user has admin privileges)
  static const String adminUsers = '/admin/users';
  static const String adminReports = '/admin/reports';
  static const String adminSettings = '/admin/settings';
  static const String adminAnalytics = '/admin/analytics';

  // System Routes
  static const String health = '/health';
  static const String version = '/version';
  static const String status = '/status';
}
