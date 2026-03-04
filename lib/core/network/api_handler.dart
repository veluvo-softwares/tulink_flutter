import 'package:dio/dio.dart';

import '../errors/failure.dart';

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
          // Try to extract message from backend response
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
}