import 'package:equatable/equatable.dart';

/// Base class for all failures
/// This class is used to represent errors in a standardized way across the app
abstract class Failure extends Equatable {
  const Failure({
    required this.message,
    this.statusCode,
  });

  final String message;
  final int? statusCode;

  @override
  List<Object?> get props => [message, statusCode];
}

/// Failure related to server/API errors
class ServerFailure extends Failure {
  const ServerFailure({
    required super.message,
    super.statusCode,
  });

  factory ServerFailure.fromStatusCode(int statusCode) {
    switch (statusCode) {
      case 400:
        return const ServerFailure(
          message: 'Bad request. Please check your input.',
          statusCode: 400,
        );
      case 401:
        return const ServerFailure(
          message: 'Authentication failed. Please login again.',
          statusCode: 401,
        );
      case 403:
        return const ServerFailure(
          message: 'Access forbidden. You don\'t have permission.',
          statusCode: 403,
        );
      case 404:
        return const ServerFailure(
          message: 'Requested resource not found.',
          statusCode: 404,
        );
      case 500:
        return const ServerFailure(
          message: 'Internal server error. Please try again later.',
          statusCode: 500,
        );
      default:
        return ServerFailure(
          message: 'Server error occurred. Status code: $statusCode',
          statusCode: statusCode,
        );
    }
  }
}

/// Failure related to cache/local storage operations
class CacheFailure extends Failure {
  const CacheFailure({
    required super.message,
  });

  static const CacheFailure read = CacheFailure(
    message: 'Failed to read data from cache',
  );

  static const CacheFailure write = CacheFailure(
    message: 'Failed to write data to cache',
  );

  static const CacheFailure delete = CacheFailure(
    message: 'Failed to delete data from cache',
  );
}

/// Failure related to network connectivity
class NetworkFailure extends Failure {
  const NetworkFailure({
    required super.message,
  });

  static const NetworkFailure noInternet = NetworkFailure(
    message: 'No internet connection. Please check your connection.',
  );

  static const NetworkFailure timeout = NetworkFailure(
    message: 'Request timeout. Please try again.',
  );

  static const NetworkFailure unknown = NetworkFailure(
    message: 'Network error occurred. Please try again.',
  );
}

/// Failure related to data validation or parsing
class ValidationFailure extends Failure {
  const ValidationFailure({
    required super.message,
  });

  static const ValidationFailure invalidEmail = ValidationFailure(
    message: 'Please enter a valid email address',
  );

  static const ValidationFailure invalidPassword = ValidationFailure(
    message: 'Password must be at least 8 characters long',
  );

  static const ValidationFailure invalidData = ValidationFailure(
    message: 'Invalid data format received',
  );
}