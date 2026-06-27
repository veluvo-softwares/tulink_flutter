import 'package:dio/dio.dart';

import '../errors/failure.dart';
import 'models/api_response.dart';
import 'models/api_response_base.dart';

/// Centralized API error handling utility
/// Provides a consistent way to handle Dio errors across all remote data sources
class ApiHandler {
  ApiHandler._();

  /// Performs an API call with centralized error handling
  /// 
  /// Example usage:
  /// ```dart
  /// final result = await ApiHandler.performApiCall<User>(
  ///   () => _dio.get('/users/123'),
  ///   (data) => UserModel.fromJson(data),
  /// );
  /// ```
  static Future<T> performApiCall<T>(
    Future<Response<dynamic>> Function() apiCall, [
    T Function(Map<String, dynamic> data)? parser,
  ]) async {
    try {
      final response = await apiCall();
      
      if (response.statusCode != null && 
          response.statusCode! >= 200 && 
          response.statusCode! < 300) {
        
        if (parser != null && response.data != null) {
          // Parse the response data if parser is provided
          return parser(response.data as Map<String, dynamic>);
        } else {
          // Return response data directly if no parser
          return response.data as T;
        }
      } else {
        throw ServerFailure.fromStatusCode(response.statusCode ?? 500);
      }
    } on DioException catch (e) {
      throw _handleDioException(e);
    } catch (e) {
      throw const ServerFailure(message: 'An unexpected error occurred');
    }
  }

  /// Performs an API call with multiple response parsers
  /// Useful for endpoints that return different data structures
  /// 
  /// Example usage:
  /// ```dart
  /// final result = await ApiHandler.performApiCallWithMultipleResults<({UserModel user, String token})>(
  ///   () => _dio.post('/auth/signin', data: credentials),
  ///   (data) => (
  ///     user: UserModel.fromJson(data['user']),
  ///     token: data['token'] as String,
  ///   ),
  /// );
  /// ```
  static Future<T> performApiCallWithMultipleResults<T>(
    Future<Response<dynamic>> Function() apiCall,
    T Function(Map<String, dynamic> data) parser,
  ) async {
    try {
      final response = await apiCall();
      
      if (response.statusCode != null && 
          response.statusCode! >= 200 && 
          response.statusCode! < 300) {
        
        final data = response.data as Map<String, dynamic>;
        return parser(data);
      } else {
        throw ServerFailure.fromStatusCode(response.statusCode ?? 500);
      }
    } on DioException catch (e) {
      throw _handleDioException(e);
    } catch (e) {
      throw const ServerFailure(message: 'An unexpected error occurred');
    }
  }

  /// Performs an API call that doesn't return data (like DELETE, some POST)
  /// 
  /// Example usage:
  /// ```dart
  /// await ApiHandler.performVoidApiCall(
  ///   () => _dio.delete('/users/123'),
  /// );
  /// ```
  static Future<void> performVoidApiCall(
    Future<Response<dynamic>> Function() apiCall,
  ) async {
    try {
      final response = await apiCall();
      
      if (response.statusCode == null || 
          response.statusCode! < 200 || 
          response.statusCode! >= 300) {
        throw ServerFailure.fromStatusCode(response.statusCode ?? 500);
      }
    } on DioException catch (e) {
      throw _handleDioException(e);
    } catch (e) {
      throw const ServerFailure(message: 'An unexpected error occurred');
    }
  }

  /// Centralized Dio exception handling
  static Failure _handleDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return NetworkFailure.timeout;
        
      case DioExceptionType.connectionError:
        return NetworkFailure.noInternet;
        
      case DioExceptionType.badResponse:
        if (e.response != null) {
          // Prefer the backend's typed machine code (`{ error: { code, ... } }`)
          // when present, so callers can branch on it — auth refresh-vs-logout,
          // maps upstream classification, journey conflicts — instead of
          // flattening every failure by HTTP status code.
          final typed = _failureFromResponseData(
            e.response!.data,
            e.response!.statusCode,
          );
          if (typed != null) return typed;

          // No typed error body — fall back to message / status-code mapping.
          try {
            final responseData = e.response!.data;
            if (responseData is Map<String, dynamic> &&
                responseData.containsKey('message')) {
              return ServerFailure(
                message: responseData['message'] as String,
                statusCode: e.response!.statusCode,
              );
            }
          } catch (_) {
            // Fallback to status code based message
          }
          return ServerFailure.fromStatusCode(e.response!.statusCode ?? 500);
        }
        return NetworkFailure.unknown;
        
      case DioExceptionType.cancel:
        return const ServerFailure(message: 'Request was cancelled');
        
      case DioExceptionType.badCertificate:
        return const ServerFailure(message: 'Certificate verification failed');
        
      case DioExceptionType.unknown:
      default:
        return NetworkFailure.unknown;
    }
  }

  /// Parse the backend's structured error envelope `{ error: { code, ... } }`
  /// from a response body. Returns null when there is no machine `code` to act
  /// on. Exposed so callers that don't go through [performApiCall] (e.g. the
  /// raw-Dio journey data source handling `409 ALREADY_IN_ACTIVE_JOURNEY`) can
  /// read `activeJourneyId` and other typed fields off the same model.
  static ApiError? extractApiError(dynamic responseData) {
    if (responseData is! Map<String, dynamic>) return null;
    final errorObj = responseData['error'];
    if (errorObj is! Map<String, dynamic>) return null;
    if (errorObj['code'] is! String) return null;
    try {
      return ApiError.fromJson(errorObj);
    } catch (_) {
      return null;
    }
  }

  /// Map a typed backend error body to a [Failure]. Returns null when the body
  /// has no machine code (the caller then falls back to status-code mapping).
  static Failure? _failureFromResponseData(
    dynamic responseData,
    int? statusCode,
  ) {
    final apiError = extractApiError(responseData);
    if (apiError == null) return null;
    final message = (responseData is Map<String, dynamic>
            ? responseData['message'] as String?
            : null) ??
        apiError.details ??
        'Request failed';
    return _failureForCode(apiError, message, statusCode);
  }

  static Failure _failureForCode(
    ApiError error,
    String message,
    int? statusCode,
  ) {
    switch (error.code) {
      case ApiErrorCodes.tokenExpired:
        // Recoverable via refresh; the auth interceptor handles the retry.
        return AuthFailure.tokenExpired;
      case ApiErrorCodes.tokenRevoked:
      case ApiErrorCodes.authFailed:
      case ApiErrorCodes.unauthorized:
        // Not recoverable by refresh — re-auth required.
        return AuthFailure.tokenInvalid;
      case ApiErrorCodes.forbidden:
        return const AuthFailure(message: 'Access forbidden');
      case ApiErrorCodes.validationError:
        return ValidationFailure(message: message);
      default:
        // Includes UPSTREAM_* and ALREADY_IN_ACTIVE_JOURNEY: preserve the
        // machine code in `details` so it isn't lost to a generic status
        // mapping. Endpoint-specific handlers (e.g. journey conflict) read the
        // richer fields via [extractApiError] before reaching here.
        return ServerFailure(
          message: message,
          statusCode: statusCode,
          details: error.code,
        );
    }
  }

  /// Helper method for endpoints that return a list
  /// 
  /// Example usage:
  /// ```dart
  /// final users = await ApiHandler.performListApiCall<UserModel>(
  ///   () => _dio.get('/users'),
  ///   (item) => UserModel.fromJson(item),
  /// );
  /// ```
  static Future<List<T>> performListApiCall<T>(
    Future<Response<dynamic>> Function() apiCall,
    T Function(Map<String, dynamic> item) parser,
  ) async {
    try {
      final response = await apiCall();
      
      if (response.statusCode != null && 
          response.statusCode! >= 200 && 
          response.statusCode! < 300) {
        
        final List<dynamic> data = response.data as List<dynamic>;
        return data
            .map((item) => parser(item as Map<String, dynamic>))
            .toList();
      } else {
        throw ServerFailure.fromStatusCode(response.statusCode ?? 500);
      }
    } on DioException catch (e) {
      throw _handleDioException(e);
    } catch (e) {
      throw const ServerFailure(message: 'An unexpected error occurred');
    }
  }

  /// Helper method for paginated endpoints
  /// 
  /// Example usage:
  /// ```dart
  /// final result = await ApiHandler.performPaginatedApiCall<UserModel>(
  ///   () => _dio.get('/users?page=1&limit=20'),
  ///   (item) => UserModel.fromJson(item),
  /// );
  /// ```
  static Future<({List<T> data, int total, bool hasMore})> performPaginatedApiCall<T>(
    Future<Response<dynamic>> Function() apiCall,
    T Function(Map<String, dynamic> item) parser,
  ) async {
    try {
      final response = await apiCall();
      
      if (response.statusCode != null && 
          response.statusCode! >= 200 && 
          response.statusCode! < 300) {
        
        final responseData = response.data as Map<String, dynamic>;
        final List<dynamic> items = responseData['data'] as List<dynamic>;
        final int total = responseData['total'] as int;
        final bool hasMore = responseData['hasMore'] as bool? ?? false;
        
        final data = items
            .map((item) => parser(item as Map<String, dynamic>))
            .toList();
        
        return (data: data, total: total, hasMore: hasMore);
      } else {
        throw ServerFailure.fromStatusCode(response.statusCode ?? 500);
      }
    } on DioException catch (e) {
      throw _handleDioException(e);
    } catch (e) {
      throw const ServerFailure(message: 'An unexpected error occurred');
    }
  }

  // ====== NEW STANDARDIZED RESPONSE METHODS ======

  /// Performs an API call expecting a standardized ApiResponse<T> format
  /// 
  /// Handles the standard response structure:
  /// ```json
  /// {
  ///   "success": true,
  ///   "statusCode": 200,
  ///   "message": "Operation completed successfully",
  ///   "data": {...}
  /// }
  /// ```
  /// 
  /// Example usage:
  /// ```dart
  /// final result = await ApiHandler.performStandardApiCall<UserModel>(
  ///   () => _dio.get('/users/123'),
  ///   (data) => UserModel.fromJson(data),
  /// );
  /// ```
  static Future<T> performStandardApiCall<T>(
    Future<Response<dynamic>> Function() apiCall,
    T Function(Map<String, dynamic> data) parser,
  ) async {
    try {
      final response = await apiCall();
      
      if (response.statusCode != null && 
          response.statusCode! >= 200 && 
          response.statusCode! < 300) {
        
        final apiResponse = ApiResponse<Map<String, dynamic>>.fromJson(
          response.data! as Map<String, dynamic>,
          (json) => json! as Map<String, dynamic>,
        );

        if (apiResponse.success && apiResponse.data != null) {
          return parser(apiResponse.data!);
        } else {
          // Handle API-level error response
          throw _handleStandardApiError(apiResponse);
        }
      } else {
        throw ServerFailure.fromStatusCode(response.statusCode ?? 500);
      }
    } on DioException catch (e) {
      throw _handleDioException(e);
    } catch (e) {
      if (e is Failure) rethrow;
      throw const ServerFailure(message: 'An unexpected error occurred');
    }
  }

  /// Performs an API call expecting a standardized ApiResponseBase format
  /// Used for operations that don't return data (DELETE, some POST endpoints)
  /// 
  /// Handles the standard response structure:
  /// ```json
  /// {
  ///   "success": true,
  ///   "statusCode": 200,
  ///   "message": "Operation completed successfully"
  /// }
  /// ```
  /// 
  /// Example usage:
  /// ```dart
  /// await ApiHandler.performStandardVoidApiCall(
  ///   () => _dio.delete('/users/123'),
  /// );
  /// ```
  static Future<void> performStandardVoidApiCall(
    Future<Response<dynamic>> Function() apiCall,
  ) async {
    try {
      final response = await apiCall();
      
      if (response.statusCode != null && 
          response.statusCode! >= 200 && 
          response.statusCode! < 300) {
        
        final apiResponse = ApiResponseBase.fromJson(
          response.data! as Map<String, dynamic>,
        );

        if (!apiResponse.success) {
          // Handle API-level error response
          throw _handleStandardApiBaseError(apiResponse);
        }
      } else {
        throw ServerFailure.fromStatusCode(response.statusCode ?? 500);
      }
    } on DioException catch (e) {
      throw _handleDioException(e);
    } catch (e) {
      if (e is Failure) rethrow;
      throw const ServerFailure(message: 'An unexpected error occurred');
    }
  }

  /// Performs an API call expecting a standardized response with multiple data
  /// 
  /// Example for auth endpoints that return both user and token:
  /// ```dart
  /// final result = await ApiHandler.performStandardMultiDataApiCall<
  ///   ({UserModel user, String token})
  /// >(
  ///   () => _dio.post('/auth/signin', data: credentials),
  ///   (data) => (
  ///     user: UserModel.fromJson(data['user']),
  ///     token: data['tokens']['idToken'] as String,
  ///   ),
  /// );
  /// ```
  static Future<T> performStandardMultiDataApiCall<T>(
    Future<Response<dynamic>> Function() apiCall,
    T Function(Map<String, dynamic> data) parser,
  ) async {
    try {
      final response = await apiCall();
      
      if (response.statusCode != null && 
          response.statusCode! >= 200 && 
          response.statusCode! < 300) {
        
        final apiResponse = ApiResponse<Map<String, dynamic>>.fromJson(
          response.data! as Map<String, dynamic>,
          (json) => json! as Map<String, dynamic>,
        );

        if (apiResponse.success && apiResponse.data != null) {
          return parser(apiResponse.data!);
        } else {
          // Handle API-level error response
          throw _handleStandardApiError(apiResponse);
        }
      } else {
        throw ServerFailure.fromStatusCode(response.statusCode ?? 500);
      }
    } on DioException catch (e) {
      throw _handleDioException(e);
    } catch (e) {
      if (e is Failure) rethrow;
      throw const ServerFailure(message: 'An unexpected error occurred');
    }
  }

  /// Enhanced error handling for standardized responses
  /// Extracts error details from ApiResponse error structure
  static Failure _handleStandardApiError(ApiResponse<dynamic> apiResponse) {
    final error = apiResponse.error;
    if (error != null) {
      // Map specific error codes to appropriate failure types
      switch (error.code) {
        case ApiErrorCodes.unauthorized:
        case ApiErrorCodes.tokenExpired:
          return AuthFailure(message: apiResponse.message);
        case ApiErrorCodes.forbidden:
          return const AuthFailure(message: 'Access forbidden');
        case ApiErrorCodes.validationError:
          return ValidationFailure(message: error.details ?? apiResponse.message);
        case ApiErrorCodes.networkError:
        case ApiErrorCodes.timeoutError:
          return NetworkFailure.timeout;
        case ApiErrorCodes.notFound:
          return ServerFailure(
            message: apiResponse.message,
            statusCode: 404,
          );
        default:
          return ServerFailure(
            message: apiResponse.message,
            statusCode: apiResponse.statusCode,
          );
      }
    }
    
    return ServerFailure(
      message: apiResponse.message,
      statusCode: apiResponse.statusCode,
    );
  }

  /// Enhanced error handling for standardized base responses
  /// Extracts error details from ApiResponseBase error structure
  static Failure _handleStandardApiBaseError(ApiResponseBase apiResponse) {
    final error = apiResponse.error;
    if (error != null) {
      // Map specific error codes to appropriate failure types
      switch (error.code) {
        case ApiErrorCodes.unauthorized:
        case ApiErrorCodes.tokenExpired:
          return AuthFailure(message: apiResponse.message);
        case ApiErrorCodes.forbidden:
          return const AuthFailure(message: 'Access forbidden');
        case ApiErrorCodes.validationError:
          return ValidationFailure(message: error.details ?? apiResponse.message);
        case ApiErrorCodes.networkError:
        case ApiErrorCodes.timeoutError:
          return NetworkFailure.timeout;
        case ApiErrorCodes.notFound:
          return ServerFailure(
            message: apiResponse.message,
            statusCode: 404,
          );
        default:
          return ServerFailure(
            message: apiResponse.message,
            statusCode: apiResponse.statusCode,
          );
      }
    }
    
    return ServerFailure(
      message: apiResponse.message,
      statusCode: apiResponse.statusCode,
    );
  }
}
