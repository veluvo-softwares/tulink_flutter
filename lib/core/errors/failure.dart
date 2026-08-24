import 'package:equatable/equatable.dart';

/// Base class for all failures
/// This class is used to represent errors in a standardized way across the app
abstract class Failure extends Equatable {
  const Failure({
    required this.message,
    this.statusCode,
    this.details,
    this.timestamp,
  });

  final String message;
  final int? statusCode;
  final String? details;
  final DateTime? timestamp;

  @override
  List<Object?> get props => [message, statusCode, details, timestamp];

  /// Create a copy with optional overrides
  Failure copyWith({
    String? message,
    int? statusCode,
    String? details,
    DateTime? timestamp,
  });
}

/// Failure related to server/API errors
class ServerFailure extends Failure {
  const ServerFailure({
    required super.message,
    super.statusCode,
    super.details,
    super.timestamp,
  });

  factory ServerFailure.fromStatusCode(int statusCode) {
    switch (statusCode) {
      case 400:
        return ServerFailure(
          message: 'Bad request. Please check your input.',
          statusCode: 400,
          details: 'The request was malformed or invalid.',
          timestamp: DateTime.now(),
        );
      case 401:
        return ServerFailure(
          message: 'Authentication failed. Please login again.',
          statusCode: 401,
          details: 'Your session has expired or credentials are invalid.',
          timestamp: DateTime.now(),
        );
      case 403:
        return ServerFailure(
          message: 'Access forbidden. You don\'t have permission.',
          statusCode: 403,
          details: 'You are not authorized to access this resource.',
          timestamp: DateTime.now(),
        );
      case 404:
        return ServerFailure(
          message: 'Requested resource not found.',
          statusCode: 404,
          details: 'The resource you are looking for does not exist.',
          timestamp: DateTime.now(),
        );
      case 409:
        return ServerFailure(
          message: 'Conflict. Resource already exists.',
          statusCode: 409,
          details: 'The resource you are trying to create already exists.',
          timestamp: DateTime.now(),
        );
      case 422:
        return ServerFailure(
          message: 'Validation error. Please check your input.',
          statusCode: 422,
          details: 'The request data failed validation.',
          timestamp: DateTime.now(),
        );
      case 429:
        return ServerFailure(
          message: 'Too many requests. Please try again later.',
          statusCode: 429,
          details: 'Rate limit exceeded. Please wait before retrying.',
          timestamp: DateTime.now(),
        );
      case 500:
        return ServerFailure(
          message: 'Internal server error. Please try again later.',
          statusCode: 500,
          details: 'An unexpected error occurred on the server.',
          timestamp: DateTime.now(),
        );
      case 502:
        return ServerFailure(
          message: 'Server is temporarily unavailable.',
          statusCode: 502,
          details: 'Bad gateway error. Please try again later.',
          timestamp: DateTime.now(),
        );
      case 503:
        return ServerFailure(
          message: 'Service unavailable. Please try again later.',
          statusCode: 503,
          details: 'The server is temporarily overloaded or down.',
          timestamp: DateTime.now(),
        );
      case 504:
        return ServerFailure(
          message: 'Request timeout. Please try again.',
          statusCode: 504,
          details: 'Gateway timeout occurred.',
          timestamp: DateTime.now(),
        );
      default:
        return ServerFailure(
          message: 'Server error occurred. Status code: $statusCode',
          statusCode: statusCode,
          details: 'An unexpected server error occurred.',
          timestamp: DateTime.now(),
        );
    }
  }

  @override
  ServerFailure copyWith({
    String? message,
    int? statusCode,
    String? details,
    DateTime? timestamp,
  }) {
    return ServerFailure(
      message: message ?? this.message,
      statusCode: statusCode ?? this.statusCode,
      details: details ?? this.details,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

/// Failure related to cache/local storage operations
class CacheFailure extends Failure {
  const CacheFailure({required super.message, super.details, super.timestamp});

  static CacheFailure read = CacheFailure(
    message: 'Failed to read data from cache',
    details: 'An error occurred while reading cached data.',
    timestamp: DateTime.now(),
  );

  static CacheFailure write = CacheFailure(
    message: 'Failed to write data to cache',
    details: 'An error occurred while writing data to cache.',
    timestamp: DateTime.now(),
  );

  static CacheFailure delete = CacheFailure(
    message: 'Failed to delete data from cache',
    details: 'An error occurred while deleting cached data.',
    timestamp: DateTime.now(),
  );

  static CacheFailure corrupted = CacheFailure(
    message: 'Cached data is corrupted',
    details: 'The cached data appears to be corrupted or invalid.',
    timestamp: DateTime.now(),
  );

  @override
  CacheFailure copyWith({
    String? message,
    int? statusCode,
    String? details,
    DateTime? timestamp,
  }) {
    return CacheFailure(
      message: message ?? this.message,
      details: details ?? this.details,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

/// Failure related to network connectivity
class NetworkFailure extends Failure {
  const NetworkFailure({
    required super.message,
    super.details,
    super.timestamp,
  });

  static NetworkFailure noInternet = NetworkFailure(
    message: 'No internet connection. Please check your connection.',
    details: 'Unable to establish network connection.',
    timestamp: DateTime.now(),
  );

  static NetworkFailure timeout = NetworkFailure(
    message: 'Request timeout. Please try again.',
    details: 'The request took too long to complete.',
    timestamp: DateTime.now(),
  );

  static NetworkFailure connectionError = NetworkFailure(
    message: 'Connection error. Please check your internet.',
    details: 'Failed to connect to the server.',
    timestamp: DateTime.now(),
  );

  static NetworkFailure unknown = NetworkFailure(
    message: 'Network error occurred. Please try again.',
    details: 'An unexpected network error occurred.',
    timestamp: DateTime.now(),
  );

  /// Search-specific network error
  static NetworkFailure searchConnection = NetworkFailure(
    message: 'Connection problem :(\nPlease check your internet and try again',
    details: 'Unable to connect to search service.',
    timestamp: DateTime.now(),
  );

  @override
  NetworkFailure copyWith({
    String? message,
    int? statusCode,
    String? details,
    DateTime? timestamp,
  }) {
    return NetworkFailure(
      message: message ?? this.message,
      details: details ?? this.details,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

/// Failure related to data validation or parsing
class ValidationFailure extends Failure {
  const ValidationFailure({
    required super.message,
    super.details,
    super.timestamp,
    this.fieldErrors,
  });

  final Map<String, String>? fieldErrors;

  static ValidationFailure invalidEmail = ValidationFailure(
    message: 'Please enter a valid email address',
    details: 'The email format is not valid.',
    timestamp: DateTime.now(),
  );

  static ValidationFailure invalidPassword = ValidationFailure(
    message: 'Password must be at least 8 characters long',
    details:
        'Password should contain at least 8 characters with a mix of letters and numbers.',
    timestamp: DateTime.now(),
  );

  static ValidationFailure weakPassword = ValidationFailure(
    message: 'Password is too weak',
    details:
        'Please use a stronger password with uppercase, lowercase, numbers, and symbols.',
    timestamp: DateTime.now(),
  );

  static ValidationFailure passwordMismatch = ValidationFailure(
    message: 'Passwords do not match',
    details: 'The password confirmation does not match the password.',
    timestamp: DateTime.now(),
  );

  static ValidationFailure invalidName = ValidationFailure(
    message: 'Please enter a valid name',
    details: 'Name should be at least 2 characters long.',
    timestamp: DateTime.now(),
  );

  static ValidationFailure invalidData = ValidationFailure(
    message: 'Invalid data format received',
    details: 'The data received from the server is in an unexpected format.',
    timestamp: DateTime.now(),
  );

  static ValidationFailure requiredField = ValidationFailure(
    message: 'This field is required',
    details: 'Please fill in all required fields.',
    timestamp: DateTime.now(),
  );

  @override
  ValidationFailure copyWith({
    String? message,
    int? statusCode,
    String? details,
    DateTime? timestamp,
  }) {
    return ValidationFailure(
      message: message ?? this.message,
      details: details ?? this.details,
      timestamp: timestamp ?? this.timestamp,
      fieldErrors: fieldErrors,
    );
  }

  /// Create validation failure with field-specific errors
  factory ValidationFailure.withFieldErrors({
    required String message,
    required Map<String, String> fieldErrors,
    String? details,
  }) {
    return ValidationFailure(
      message: message,
      fieldErrors: fieldErrors,
      details: details ?? 'Multiple validation errors occurred.',
      timestamp: DateTime.now(),
    );
  }
}

/// Failure related to authentication and authorization
class AuthFailure extends Failure {
  /// Creates an authentication failure
  const AuthFailure({
    required super.message,
    super.statusCode,
    super.details,
    super.timestamp,
    this.isRetryable = false,
    this.requiresReauth = false,
  });

  final bool isRetryable;
  final bool requiresReauth;

  /// Invalid credentials error
  static AuthFailure invalidCredentials = AuthFailure(
    message: 'Invalid email or password',
    statusCode: 401,
    details: 'The email or password you entered is incorrect.',
    timestamp: DateTime.now(),
    isRetryable: true,
  );

  /// Token expired error
  static AuthFailure tokenExpired = AuthFailure(
    message: 'Session expired. Please login again',
    statusCode: 401,
    details: 'Your authentication token has expired.',
    timestamp: DateTime.now(),
    requiresReauth: true,
  );

  /// Token invalid error
  static AuthFailure tokenInvalid = AuthFailure(
    message: 'Invalid session. Please login again',
    statusCode: 401,
    details: 'Your authentication token is invalid or corrupted.',
    timestamp: DateTime.now(),
    requiresReauth: true,
  );

  /// Refresh token expired
  static AuthFailure refreshTokenExpired = AuthFailure(
    message: 'Session cannot be refreshed. Please login again',
    statusCode: 401,
    details: 'Both access and refresh tokens have expired.',
    timestamp: DateTime.now(),
    requiresReauth: true,
  );

  /// Access denied error
  static AuthFailure accessDenied = AuthFailure(
    message: 'Access denied. Insufficient permissions',
    statusCode: 403,
    details: 'You do not have the required permissions for this action.',
    timestamp: DateTime.now(),
  );

  /// Account locked
  static AuthFailure accountLocked = AuthFailure(
    message: 'Account temporarily locked. Try again later',
    statusCode: 423,
    details:
        'Your account has been temporarily locked due to multiple failed login attempts.',
    timestamp: DateTime.now(),
    isRetryable: true,
  );

  /// Account suspended
  static AuthFailure accountSuspended = AuthFailure(
    message: 'Account suspended. Contact support',
    statusCode: 403,
    details:
        'Your account has been suspended. Please contact support for assistance.',
    timestamp: DateTime.now(),
  );

  /// Email not verified
  static AuthFailure emailNotVerified = AuthFailure(
    message: 'Please verify your email address',
    statusCode: 403,
    details: 'You need to verify your email address before proceeding.',
    timestamp: DateTime.now(),
    isRetryable: true,
  );

  /// User already exists
  static AuthFailure userAlreadyExists = AuthFailure(
    message: 'An account with this email already exists',
    statusCode: 409,
    details: 'Please use a different email address or try logging in.',
    timestamp: DateTime.now(),
    isRetryable: true,
  );

  /// Benign sentinel: the user backed out of a native social sign-in flow
  /// (Google/Apple). The provider ignores this — it must NEVER surface an error
  /// toast. Const so [isCancellation] can identity-check it.
  static const AuthFailure cancelled = AuthFailure(
    message: '',
    details: 'Social sign-in was cancelled by the user.',
  );

  /// True only for the [cancelled] sentinel — callers use this to silently drop
  /// a user-cancelled flow instead of showing an error.
  bool get isCancellation => identical(this, AuthFailure.cancelled);

  @override
  AuthFailure copyWith({
    String? message,
    int? statusCode,
    String? details,
    DateTime? timestamp,
  }) {
    return AuthFailure(
      message: message ?? this.message,
      statusCode: statusCode ?? this.statusCode,
      details: details ?? this.details,
      timestamp: timestamp ?? this.timestamp,
      isRetryable: isRetryable,
      requiresReauth: requiresReauth,
    );
  }
}

/// Failure related to search operations
class SearchFailure extends Failure {
  const SearchFailure({
    required super.message,
    super.details,
    super.timestamp,
    this.searchQuery,
  });

  final String? searchQuery;

  /// No results found for search query
  static SearchFailure noResults(String query) => SearchFailure(
    message: 'No places found :(\nTry searching with a different term',
    details: 'Search query "$query" returned no results.',
    timestamp: DateTime.now(),
    searchQuery: query,
  );

  /// Search service temporarily unavailable
  static SearchFailure serviceUnavailable = SearchFailure(
    message: 'Search service unavailable :(\nPlease try again later',
    details: 'The search service is temporarily down or unreachable.',
    timestamp: DateTime.now(),
  );

  /// Invalid search query format
  static SearchFailure invalidQuery(String query) => SearchFailure(
    message: 'Search not found :(\nTry a different search term',
    details: 'The search query "$query" is invalid or malformed.',
    timestamp: DateTime.now(),
    searchQuery: query,
  );

  /// Search request limit exceeded
  static SearchFailure rateLimitExceeded = SearchFailure(
    message: 'Too many searches :(\nPlease wait a moment and try again',
    details: 'Search rate limit has been exceeded.',
    timestamp: DateTime.now(),
  );

  /// Search access denied
  static SearchFailure accessDenied = SearchFailure(
    message: 'Search access denied :(\nPlease restart the app',
    details: 'Access to search service has been denied.',
    timestamp: DateTime.now(),
  );

  /// Benign sentinel: the search request was cancelled/superseded (a newer
  /// search started or the field was cleared). The provider ignores this — it
  /// must NEVER surface an error card. Const so `isCancellation` can identity-check.
  static const SearchFailure cancelled = SearchFailure(
    message: '',
    details: 'Search request was cancelled (superseded or field cleared).',
  );

  /// True only for the [cancelled] sentinel — callers use this to silently drop
  /// aborted requests instead of rendering an error.
  bool get isCancellation => identical(this, SearchFailure.cancelled);

  @override
  SearchFailure copyWith({
    String? message,
    int? statusCode,
    String? details,
    DateTime? timestamp,
  }) {
    return SearchFailure(
      message: message ?? this.message,
      details: details ?? this.details,
      timestamp: timestamp ?? this.timestamp,
      searchQuery: searchQuery,
    );
  }
}

/// Failure related to token management
class TokenFailure extends Failure {
  const TokenFailure({
    required super.message,
    super.details,
    super.timestamp,
    this.tokenType,
    this.requiresReauth = false,
  });

  final String? tokenType;
  final bool requiresReauth;

  static TokenFailure accessTokenExpired = TokenFailure(
    message: 'Access token expired',
    details: 'The access token has expired and needs to be refreshed.',
    timestamp: DateTime.now(),
    tokenType: 'access',
  );

  static TokenFailure refreshTokenExpired = TokenFailure(
    message: 'Refresh token expired',
    details: 'The refresh token has expired. Re-authentication required.',
    timestamp: DateTime.now(),
    tokenType: 'refresh',
    requiresReauth: true,
  );

  /// A token refresh could NOT be completed for a transient reason — no
  /// internet, a timeout, or a 5xx / 503 from the backend's refresh endpoint.
  /// Crucially [requiresReauth] is false: the session is still valid, so callers
  /// must fail the current request softly and keep the stored tokens rather than
  /// signing the user out. Recovery happens on the next attempt / reconnect.
  /// This is what prevents a brief offline blip or an upstream hiccup from
  /// destroying an active session mid-journey.
  static TokenFailure refreshTransient = TokenFailure(
    message: 'Could not refresh session right now',
    details:
        'The token refresh failed for a transient reason (offline or server '
        'temporarily unavailable). The session is preserved; retry shortly.',
    timestamp: DateTime.now(),
    tokenType: 'refresh',
    requiresReauth: false,
  );

  static TokenFailure tokenCorrupted = TokenFailure(
    message: 'Token is corrupted',
    details: 'The stored token appears to be corrupted or invalid.',
    timestamp: DateTime.now(),
    requiresReauth: true,
  );

  static TokenFailure tokenMissing = TokenFailure(
    message: 'Token not found',
    details: 'No authentication token found in secure storage.',
    timestamp: DateTime.now(),
    requiresReauth: true,
  );

  @override
  TokenFailure copyWith({
    String? message,
    int? statusCode,
    String? details,
    DateTime? timestamp,
  }) {
    return TokenFailure(
      message: message ?? this.message,
      details: details ?? this.details,
      timestamp: timestamp ?? this.timestamp,
      tokenType: tokenType,
      requiresReauth: requiresReauth,
    );
  }
}

/// Failure related to convoy coordination and real-time location tracking
class ConvoyFailure extends Failure {
  const ConvoyFailure({
    required super.message,
    super.details,
    super.timestamp,
    this.isRetryable = false,
  });

  final bool isRetryable;

  /// Location permission denied
  static ConvoyFailure locationPermissionDenied = ConvoyFailure(
    message: 'Location permission denied',
    details:
        'Please enable location permissions to participate in convoy coordination.',
    timestamp: DateTime.now(),
  );

  /// Location service disabled
  static ConvoyFailure locationServiceDisabled = ConvoyFailure(
    message: 'Location service disabled',
    details:
        'Please enable location services to share your position with the convoy.',
    timestamp: DateTime.now(),
  );

  /// Permission is granted and the service is on, but the device has not
  /// produced a fix yet (cold GPS, indoors, simulator with no location set).
  /// Retryable: a later fix resumes publishing without restarting the journey.
  static ConvoyFailure locationUnavailable = ConvoyFailure(
    message: 'Waiting for your location',
    details:
        'Your position has not been shared with the convoy yet. This usually '
        'resolves once the device gets a GPS fix.',
    timestamp: DateTime.now(),
    isRetryable: true,
  );

  /// GPS accuracy too low
  static ConvoyFailure gpsAccuracyLow = ConvoyFailure(
    message: 'GPS signal too weak',
    details:
        'Cannot get accurate location. Please move to an area with better GPS signal.',
    timestamp: DateTime.now(),
    isRetryable: true,
  );

  /// Real-time database connection failed
  static ConvoyFailure rtdbConnectionFailed = ConvoyFailure(
    message: 'Failed to connect to convoy coordination',
    details:
        'Cannot connect to real-time database. Please check your internet connection.',
    timestamp: DateTime.now(),
    isRetryable: true,
  );

  /// Publishing location update failed
  static ConvoyFailure publishLocationFailed = ConvoyFailure(
    message: 'Failed to update location',
    details:
        'Could not share your location with the convoy. Will retry automatically.',
    timestamp: DateTime.now(),
    isRetryable: true,
  );

  /// Rate limit exceeded
  static ConvoyFailure rateLimitExceeded = ConvoyFailure(
    message: 'Too many location updates',
    details:
        'Location updates are being sent too frequently. Please wait a moment.',
    timestamp: DateTime.now(),
    isRetryable: true,
  );

  /// Journey not active
  static ConvoyFailure journeyNotActive = ConvoyFailure(
    message: 'Journey not active',
    details: 'This journey is not currently active for convoy coordination.',
    timestamp: DateTime.now(),
  );

  /// Backend asked the client to stop polling for this journey (server-side
  /// terminal: journey completed/cancelled). Terminal — but UI must stay
  /// silent because this is expected behaviour, not an error.
  static ConvoyFailure stopPolling = ConvoyFailure(
    message: 'Server requested stop polling',
    details: 'Journey is no longer accepting location updates.',
    timestamp: DateTime.now(),
  );

  /// Not a journey member
  static ConvoyFailure notJourneyMember = ConvoyFailure(
    message: 'Not authorized for this journey',
    details: 'You are not a member of this journey convoy.',
    timestamp: DateTime.now(),
  );

  @override
  ConvoyFailure copyWith({
    String? message,
    int? statusCode,
    String? details,
    DateTime? timestamp,
  }) {
    return ConvoyFailure(
      message: message ?? this.message,
      details: details ?? this.details,
      timestamp: timestamp ?? this.timestamp,
      isRetryable: isRetryable,
    );
  }
}

/// Raised when `journey.start()` is rejected by the backend because the user
/// already has an ACTIVE journey (HTTP 409, code `ALREADY_IN_ACTIVE_JOURNEY`).
///
/// Carries [activeJourneyId] — the journey the user already has active — so the
/// UI can offer an "end it and start this one" switch instead of dead-ending on
/// a generic conflict error. This is the server's authoritative single-active
/// enforcement (BE-FIX-3); it catches cases the client-side switch guard can't
/// know about, e.g. a stale client or a second device.
class AlreadyInActiveJourneyFailure extends Failure {
  const AlreadyInActiveJourneyFailure({
    this.activeJourneyId,
    super.message = 'You already have an active journey.',
    super.details,
    super.timestamp,
  }) : super(statusCode: 409);

  /// Id of the journey the user already has ACTIVE (from the 409 body). May be
  /// null if the server resolved the conflict in the race window before we
  /// re-read it.
  final String? activeJourneyId;

  @override
  List<Object?> get props => [...super.props, activeJourneyId];

  @override
  AlreadyInActiveJourneyFailure copyWith({
    String? message,
    int? statusCode,
    String? details,
    DateTime? timestamp,
  }) {
    return AlreadyInActiveJourneyFailure(
      activeJourneyId: activeJourneyId,
      message: message ?? this.message,
      details: details ?? this.details,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
