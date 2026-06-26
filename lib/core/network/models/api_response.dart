import 'package:json_annotation/json_annotation.dart';

part 'api_response.g.dart';

/// Standard API response wrapper for all API calls
/// Provides consistent response structure across the application
@JsonSerializable(genericArgumentFactories: true)
class ApiResponse<T> {
  /// Creates an API response
  const ApiResponse({
    required this.success,
    required this.statusCode,
    required this.message,
    this.data,
    this.error,
  });

  /// Factory constructor for successful responses
  factory ApiResponse.success({
    required T data,
    int statusCode = 200,
    String message = 'Operation completed successfully',
  }) {
    return ApiResponse<T>(
      success: true,
      statusCode: statusCode,
      message: message,
      data: data,
    );
  }

  /// Factory constructor for error responses
  factory ApiResponse.error({
    required String message,
    required ApiError error,
    int statusCode = 500,
  }) {
    return ApiResponse<T>(
      success: false,
      statusCode: statusCode,
      message: message,
      error: error,
    );
  }

  /// Creates an ApiResponse from JSON
  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Object? json) fromJsonT,
  ) =>
      _$ApiResponseFromJson(json, fromJsonT);

  /// Indicates if the request was successful
  final bool success;

  /// HTTP status code
  final int statusCode;

  /// Human-readable message describing the result
  final String message;

  /// Response data (only present in successful responses)
  final T? data;

  /// Error details (only present in failed responses)
  final ApiError? error;

  /// Converts this ApiResponse to JSON
  Map<String, dynamic> toJson(Object Function(T value) toJsonT) =>
      _$ApiResponseToJson(this, toJsonT);

  @override
  String toString() {
    return 'ApiResponse(success: $success, statusCode: $statusCode, '
        'message: $message, data: $data, error: $error)';
  }
}

/// Error details for failed API responses
@JsonSerializable()
class ApiError {
  /// Creates an API error
  const ApiError({
    required this.code,
    this.details,
    this.activeJourneyId,
  });

  /// Factory constructor from JSON
  factory ApiError.fromJson(Map<String, dynamic> json) =>
      _$ApiErrorFromJson(json);

  /// Error code type (e.g., 'VALIDATION_ERROR', 'UNAUTHORIZED', etc.)
  final String code;

  /// Detailed error description. Nullable: the backend's typed error bodies
  /// (e.g. `{ code, activeJourneyId }`) often omit a `details` field.
  final String? details;

  /// Present on `409 ALREADY_IN_ACTIVE_JOURNEY` — the id of the journey the
  /// user already has ACTIVE. Lets the client drive the end-A-then-start-B
  /// confirm flow instead of surfacing a dead-end conflict error.
  final String? activeJourneyId;

  /// Convert to JSON
  Map<String, dynamic> toJson() => _$ApiErrorToJson(this);

  @override
  String toString() {
    return 'ApiError(code: $code, details: $details, '
        'activeJourneyId: $activeJourneyId)';
  }
}

/// Common error codes used across the application
abstract class ApiErrorCodes {
  /// Validation error code
  static const String validationError = 'VALIDATION_ERROR';

  /// Unauthorized access error code
  static const String unauthorized = 'UNAUTHORIZED';

  /// Forbidden access error code
  static const String forbidden = 'FORBIDDEN';

  /// Resource not found error code
  static const String notFound = 'NOT_FOUND';

  /// Server error code
  static const String serverError = 'SERVER_ERROR';

  /// Network connection error code
  static const String networkError = 'NETWORK_ERROR';

  /// Request timeout error code
  static const String timeoutError = 'TIMEOUT_ERROR';

  /// Invalid login credentials error code
  static const String invalidCredentials = 'INVALID_CREDENTIALS';

  /// Email already exists error code
  static const String emailAlreadyExists = 'EMAIL_ALREADY_EXISTS';

  /// Authentication token expired error code
  static const String tokenExpired = 'TOKEN_EXPIRED';

  /// API rate limit exceeded error code
  static const String rateLimitExceeded = 'RATE_LIMIT_EXCEEDED';

  // ===== Backend v1.0 server-side remediation codes (BE-FIX-1..3) =====

  /// Token genuinely revoked (logout / tokensValidAfter) — re-auth required,
  /// a refresh will NOT recover it.
  static const String tokenRevoked = 'TOKEN_REVOKED';

  /// Hard auth failure (bad/forged token, deleted account) — re-auth required.
  static const String authFailed = 'AUTH_FAILED';

  /// Places search upstream returned a non-2xx (502) — "upstream broke".
  static const String upstreamPlacesError = 'UPSTREAM_PLACES_ERROR';

  /// Directions upstream returned a non-2xx (502) — "upstream broke".
  static const String upstreamDirectionsError = 'UPSTREAM_DIRECTIONS_ERROR';

  /// Maps upstream timed out / was unreachable (503) — "offline / try later".
  static const String upstreamUnavailable = 'UPSTREAM_UNAVAILABLE';

  /// `journey.start()` rejected because the user already has an ACTIVE journey
  /// (409). The body carries `activeJourneyId`.
  static const String alreadyInActiveJourney = 'ALREADY_IN_ACTIVE_JOURNEY';
}
