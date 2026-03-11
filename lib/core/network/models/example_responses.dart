import 'package:tulink_flutter/core/network/models/api_response.dart';
import 'package:tulink_flutter/core/network/models/api_response_base.dart';

/// Example implementations demonstrating the standard response format
/// This file shows how to create responses that match your API spec
class ExampleResponses {
  /// Example successful response with data
  /// Matches your spec:
  /// {
  ///   "success": true,
  ///   "statusCode": 200,
  ///   "message": "Operation completed successfully",
  ///   "data": {}
  /// }
  static Map<String, dynamic> successfulAuthResponse() {
    final response = ApiResponse<Map<String, dynamic>>.success(
      data: {
        'user': {
          'id': '123',
          'email': 'user@example.com',
          'name': 'John Doe',
          'isEmailVerified': true,
          'createdAt': DateTime.now().toIso8601String(),
        },
        'tokens': {
          'idToken': 'jwt_id_token_here',
          'refreshToken': 'jwt_refresh_token_here',
        }
      },
      message: 'Authentication successful',
    );

    return response.toJson((data) => data);
  }

  /// Example error response
  /// Matches your spec:
  /// {
  ///   "success": false,
  ///   "statusCode": 401,
  ///   "message": "An error returned",
  ///   "error": {
  ///     "code": "Error code type",
  ///     "details": "error code details"
  ///   }
  /// }
  static Map<String, dynamic> errorResponse() {
    final response = ApiResponse<Map<String, dynamic>>.error(
      message: 'Invalid credentials provided',
      statusCode: 401,
      error: const ApiError(
        code: ApiErrorCodes.invalidCredentials,
        details: 'The email or password you entered is incorrect',
      ),
    );

    return response.toJson((data) => data);
  }

  /// Example successful void operation response
  /// For operations like sign out, delete, etc.
  static Map<String, dynamic> successfulVoidResponse() {
    final response = ApiResponseBase.success(
      message: 'User signed out successfully',
    );

    return response.toJson();
  }

  /// Example error void operation response
  static Map<String, dynamic> errorVoidResponse() {
    final response = ApiResponseBase.error(
      message: 'Sign out failed',
      error: const ApiError(
        code: ApiErrorCodes.serverError,
        details: 'Unable to process sign out request at this time',
      ),
    );

    return response.toJson();
  }
}
