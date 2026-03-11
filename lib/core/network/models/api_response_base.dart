import 'package:json_annotation/json_annotation.dart';

import 'package:tulink_flutter/core/network/models/api_response.dart';

part 'api_response_base.g.dart';

/// Base API response for operations that don't return data
/// Used for endpoints like sign out, delete operations, etc.
@JsonSerializable()
class ApiResponseBase {
  /// Creates a base API response
  const ApiResponseBase({
    required this.success,
    required this.statusCode,
    required this.message,
    this.error,
  });

  /// Factory constructor for successful responses
  factory ApiResponseBase.success({
    int statusCode = 200,
    String message = 'Operation completed successfully',
  }) {
    return ApiResponseBase(
      success: true,
      statusCode: statusCode,
      message: message,
    );
  }

  /// Factory constructor for error responses
  factory ApiResponseBase.error({
    required String message,
    required ApiError error,
    int statusCode = 500,
  }) {
    return ApiResponseBase(
      success: false,
      statusCode: statusCode,
      message: message,
      error: error,
    );
  }

  /// Creates an ApiResponseBase from JSON
  factory ApiResponseBase.fromJson(Map<String, dynamic> json) =>
      _$ApiResponseBaseFromJson(json);

  /// Indicates if the request was successful
  final bool success;

  /// HTTP status code
  final int statusCode;

  /// Human-readable message describing the result
  final String message;

  /// Error details (only present in failed responses)
  final ApiError? error;

  /// Converts this ApiResponseBase to JSON
  Map<String, dynamic> toJson() => _$ApiResponseBaseToJson(this);

  @override
  String toString() {
    return 'ApiResponseBase(success: $success, statusCode: $statusCode, '
        'message: $message, error: $error)';
  }
}
