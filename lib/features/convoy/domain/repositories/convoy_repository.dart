import '../entities/convoy_snapshot.dart';
import '../entities/journey_ended_event.dart';
import '../entities/member_position.dart';
import '../../../../core/errors/failure.dart';

/// Abstract repository interface for convoy coordination
/// Defines contracts for real-time position sharing and convoy management
abstract class ConvoyRepository {
  /// Stream of convoy snapshots with real-time member positions
  /// Updates automatically when any member's position changes via RTDB
  Stream<({ConvoySnapshot? snapshot, Failure? failure})> streamConvoyPositions(String journeyId);

  /// Publish current user's position to the convoy
  /// Rate limited to max 1 update per second (60/minute server limit)
  Future<({bool success, Failure? failure})> publishMyPosition({
    required String journeyId,
    required double latitude,
    required double longitude,
    required int timestamp,
    double? accuracy,
    double? altitude,
    double? heading,
    double? speed,
    Map<String, dynamic>? metadata,
  });

  /// Fetch latest convoy snapshot for cold start
  /// Used as fallback when RTDB is slow to connect
  Future<({ConvoySnapshot? snapshot, Failure? failure})> fetchLatestSnapshot(String journeyId);

  /// Stop all convoy coordination activities
  /// Cancels RTDB subscription and stops location publishing
  Future<void> stopCoordination();

  /// Get current connection state to RTDB
  Stream<ConvoyConnectionState> get connectionStateStream;

  /// Server-driven journey termination events.
  /// Fires when the backend emits `journey-ended` for the current journey.
  Stream<JourneyEndedEvent> get journeyEndedStream;
}