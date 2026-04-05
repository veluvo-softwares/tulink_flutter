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
  static const String resetPassword = '/auth/reset-password';
  static const String verifyEmail = '/auth/verify-email';
  static const String updateProfile = '/auth/profile';
  static const String deleteAccount = '/auth/account';

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
  static const String notificationSettings = '/notifications/settings';
  static String markNotificationRead(String id) => '/notifications/$id/read';
  static String markNotificationUnread(String id) => '/notifications/$id/unread';

  // Search Routes
  static const String search = '/search';
  static const String searchUsers = '/search/users';
  static const String searchPosts = '/search/posts';
  static const String searchHashtags = '/search/hashtags';

  // Analytics Routes
  static const String analytics = '/analytics';
  static const String analyticsEvents = '/analytics/events';
  static const String analyticsUserStats = '/analytics/users/stats';

  // Admin Routes (if user has admin privileges)
  static const String adminUsers = '/admin/users';
  static const String adminReports = '/admin/reports';
  static const String adminSettings = '/admin/settings';
  static const String adminAnalytics = '/admin/analytics';

  // Journey Routes
  static const String journeys = '/journeys';
  static const String activeJourneys = '/journeys/active';
  static const String myJourneys = '/journeys/my';
  
  // Dynamic Journey Routes
  static String journeyById(String id) => '/journeys/$id';
  static String startJourney(String id) => '/journeys/$id/start';
  static String stopJourney(String id) => '/journeys/$id/stop';
  static String pauseJourney(String id) => '/journeys/$id/pause';
  static String resumeJourney(String id) => '/journeys/$id/resume';
  static String journeyParticipants(String id) => '/journeys/$id/participants';
  static String journeyInvitations(String id) => '/journeys/$id/invitations';
  static String journeyRoutes(String id) => '/journeys/$id/routes';
  static String journeyProgress(String id) => '/journeys/$id/progress';

  // Invitation Routes
  static const String invitations = '/invitations';
  static const String myInvitations = '/invitations/my';
  static const String pendingInvitations = '/invitations/pending';
  static const String sentInvitations = '/invitations/sent';
  
  // Dynamic Invitation Routes
  static String invitationById(String id) => '/invitations/$id';
  static String respondToInvitation(String id) => '/invitations/$id/respond';
  static String cancelInvitation(String id) => '/invitations/$id';
  static String resendInvitation(String id) => '/invitations/$id/resend';

  // Participant Routes
  static const String participants = '/participants';
  
  // Dynamic Participant Routes
  static String participantById(String id) => '/participants/$id';
  static String removeParticipant(String journeyId, String participantId) => 
      '/journeys/$journeyId/participants/$participantId';
  static String participantLocation(String id) => '/participants/$id/location';
  static String participantStatus(String id) => '/participants/$id/status';

  // Location/Map Routes
  static const String locations = '/locations';
  static const String geocode = '/locations/geocode';
  static const String reverseGeocode = '/locations/reverse-geocode';
  static const String routeOptimization = '/locations/route-optimization';
  static const String nearbyPlaces = '/locations/nearby';
  
  // Dynamic Location Routes
  static String locationById(String id) => '/locations/$id';
  static String searchPlaces(String query) => '/locations/search?q=$query';

  // Real-time Updates (WebSocket endpoints)
  static const String wsJourneyUpdates = '/ws/journey-updates';
  static const String wsParticipantUpdates = '/ws/participant-updates';
  static const String wsLocationUpdates = '/ws/location-updates';
  
  // Dynamic WebSocket Routes
  static String wsJourneyById(String id) => '/ws/journeys/$id';
  //static String wsParticipantUpdates(String journeyId) => '/ws/journeys/$journeyId/participants';

  // System Routes
  static const String health = '/health';
  static const String version = '/version';
  static const String status = '/status';
}