/// Type-safe result handling for clean architecture
/// Replaces Dartz Either with native Dart record types
library result;

import 'package:tulink_flutter/core/errors/failure.dart';

/// A result type that represents success with data of type [T] or failure
typedef Result<T> = ({T? data, Failure? failure});

/// A result type that represents success with boolean flag or failure  
typedef BoolResult = ({bool success, Failure? failure});

/// Extension methods for Result types to make them more convenient to use
extension ResultExtension<T> on Result<T> {
  /// Whether this result represents a success
  bool get isSuccess => failure == null && data != null;
  
  /// Whether this result represents a failure
  bool get isFailure => failure != null;
  
  /// Get the data if success, otherwise throw the failure
  T get dataOrThrow {
    if (isSuccess && data != null) return data as T;
    throw Exception(failure?.message ?? 'Unknown error');
  }
  
  /// Transform the data if success, otherwise return failure
  Result<R> map<R>(R Function(T data) transform) {
    if (isSuccess && data != null) {
      try {
        return (data: transform(data as T), failure: null);
      } catch (e) {
        return (
          data: null, 
          failure: ServerFailure(message: e.toString()),
        );
      }
    }
    return (data: null, failure: failure);
  }
  
  /// Transform the data asynchronously if success, otherwise return failure
  Future<Result<R>> mapAsync<R>(
    Future<R> Function(T data) transform,
  ) async {
    if (isSuccess && data != null) {
      try {
        final result = await transform(data as T);
        return (data: result, failure: null);
      } catch (e) {
        return (
          data: null, 
          failure: ServerFailure(message: e.toString()),
        );
      }
    }
    return (data: null, failure: failure);
  }
}

extension BoolResultExtension on BoolResult {
  /// Whether this result represents a success
  bool get isSuccess => failure == null && success;
  
  /// Whether this result represents a failure
  bool get isFailure => failure != null || !success;
}

/// Helper functions for creating results
class ResultHelper {
  /// Create a successful result with data
  static Result<T> success<T>(T data) => (data: data, failure: null);
  
  /// Create a failed result with failure
  static Result<T> failure<T>(Failure failure) => 
      (data: null, failure: failure);
  
  /// Create a successful boolean result
  static BoolResult successBool() => (success: true, failure: null);
  
  /// Create a failed boolean result
  static BoolResult failureBool(Failure failure) => 
      (success: false, failure: failure);
}