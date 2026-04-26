import '../entities/convoy_snapshot.dart';
import '../repositories/convoy_repository.dart';
import '../../../../core/errors/failure.dart';

/// Use case for fetching the latest convoy snapshot via REST API
/// Used for cold start when RTDB connection is slow
class FetchLatestSnapshot {
  const FetchLatestSnapshot(this._repository);

  final ConvoyRepository _repository;

  /// Fetch the latest convoy snapshot from the server
  /// Used as fallback when real-time stream is not yet available
  Future<({ConvoySnapshot? snapshot, Failure? failure})> call(String journeyId) {
    return _repository.fetchLatestSnapshot(journeyId);
  }
}