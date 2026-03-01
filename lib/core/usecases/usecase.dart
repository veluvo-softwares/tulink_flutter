import 'package:equatable/equatable.dart';

import '../errors/failure.dart';

/// Base class for all use cases
/// [Type] is the type that the use case returns
/// [Params] is the type of the parameters passed to the use case
abstract class UseCase<Type, Params> {
  /// Execute the use case
  Future<({Type? data, Failure? failure})> call(Params params);
}

/// Use case that doesn't require parameters
abstract class NoParamsUseCase<Type> {
  /// Execute the use case without parameters
  Future<({Type? data, Failure? failure})> call();
}

/// Base class for all use case parameters
abstract class Params extends Equatable {}

/// Empty parameters for use cases that don't require parameters
class NoParams extends Params {
  @override
  List<Object?> get props => [];
}