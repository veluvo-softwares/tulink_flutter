import '../entities/convoy_snapshot.dart';
import '../repositories/convoy_repository.dart';
import '../../../../core/errors/failure.dart';

/// Use case for streaming real-time convoy positions
/// Returns a stream of convoy snapshots that updates as members move
class StreamConvoyPositions {
  const StreamConvoyPositions(this._repository);

  final ConvoyRepository _repository;

  /// Stream convoy positions for a given journey
  /// Automatically updates when any member's position changes
  Stream<({ConvoySnapshot? snapshot, Failure? failure})> call(String journeyId) {
    return _repository.streamConvoyPositions(journeyId);
  }
}