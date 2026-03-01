/// Centralized API endpoint definitions
/// Contains all base URLs and endpoint paths as constants
/// This improves maintainability and eliminates hardcoded strings
class ApiEndpoints {
  ApiEndpoints._();

  // Base URLs
  static const String baseUrl = 'https://api.example.com';
  static const String apiVersion = '/v1';

  // Authentication endpoints
  static const String signIn = '/auth/signin';
  static const String signUp = '/auth/signup';
  static const String signOut = '/auth/signout';
  static const String refreshToken = '/auth/refresh';
  static const String currentUser = '/auth/me';
  static const String resetPassword = '/auth/reset-password';
  static const String verifyEmail = '/auth/verify-email';
  static const String updateProfile = '/auth/profile';
  static const String deleteAccount = '/auth/account';

  // User management endpoints
  static const String users = '/users';
  static String userById(String id) => '/users/$id';
  static const String userSearch = '/users/search';
  static const String userPreferences = '/users/preferences';

  // Content endpoints
  static const String posts = '/posts';
  static String postById(String id) => '/posts/$id';
  static String postComments(String postId) => '/posts/$postId/comments';
  static String commentById(String postId, String commentId) => 
      '/posts/$postId/comments/$commentId';

  // File upload endpoints
  static const String uploadImage = '/files/images';
  static const String uploadDocument = '/files/documents';
  static String downloadFile(String fileId) => '/files/$fileId/download';

  // Notification endpoints
  static const String notifications = '/notifications';
  static String markNotificationRead(String id) => '/notifications/$id/read';
  static const String notificationSettings = '/notifications/settings';

  // Analytics endpoints
  static const String analytics = '/analytics';
  static const String analyticsEvents = '/analytics/events';
  static const String analyticsUserStats = '/analytics/users/stats';

  // Admin endpoints
  static const String adminUsers = '/admin/users';
  static const String adminReports = '/admin/reports';
  static const String adminSettings = '/admin/settings';

  // Health check endpoints
  static const String health = '/health';
  static const String version = '/version';

  // Helper methods for dynamic endpoint construction
  
  /// Constructs a full URL with base URL and version
  static String fullUrl(String endpoint) {
    return '$baseUrl$apiVersion$endpoint';
  }

  /// Constructs paginated endpoint with query parameters
  static String paginated(String baseEndpoint, {
    int? page,
    int? limit,
    String? sortBy,
    String? sortOrder,
  }) {
    final buffer = StringBuffer(baseEndpoint);
    final queryParams = <String>[];

    if (page != null) queryParams.add('page=$page');
    if (limit != null) queryParams.add('limit=$limit');
    if (sortBy != null) queryParams.add('sortBy=$sortBy');
    if (sortOrder != null) queryParams.add('sortOrder=$sortOrder');

    if (queryParams.isNotEmpty) {
      buffer.write('?${queryParams.join('&')}');
    }

    return buffer.toString();
  }

  /// Constructs search endpoint with query parameters
  static String search(String baseEndpoint, {
    required String query,
    List<String>? filters,
    int? page,
    int? limit,
  }) {
    final buffer = StringBuffer(baseEndpoint);
    final queryParams = <String>['q=${Uri.encodeComponent(query)}'];

    if (filters != null && filters.isNotEmpty) {
      for (final filter in filters) {
        queryParams.add('filter=${Uri.encodeComponent(filter)}');
      }
    }
    if (page != null) queryParams.add('page=$page');
    if (limit != null) queryParams.add('limit=$limit');

    buffer.write('?${queryParams.join('&')}');
    return buffer.toString();
  }
}

/// HTTP Methods constants
class HttpMethods {
  HttpMethods._();

  static const String get = 'GET';
  static const String post = 'POST';
  static const String put = 'PUT';
  static const String patch = 'PATCH';
  static const String delete = 'DELETE';
  static const String head = 'HEAD';
  static const String options = 'OPTIONS';
}

/// Common HTTP headers
class HttpHeaders {
  HttpHeaders._();

  static const String authorization = 'Authorization';
  static const String contentType = 'Content-Type';
  static const String accept = 'Accept';
  static const String userAgent = 'User-Agent';
  static const String cacheControl = 'Cache-Control';
  static const String etag = 'ETag';
  static const String ifNoneMatch = 'If-None-Match';
  static const String lastModified = 'Last-Modified';
  static const String ifModifiedSince = 'If-Modified-Since';
}

/// Content types
class ContentTypes {
  ContentTypes._();

  static const String json = 'application/json';
  static const String formData = 'multipart/form-data';
  static const String urlEncoded = 'application/x-www-form-urlencoded';
  static const String textPlain = 'text/plain';
  static const String textHtml = 'text/html';
  static const String imageJpeg = 'image/jpeg';
  static const String imagePng = 'image/png';
  static const String applicationPdf = 'application/pdf';
}