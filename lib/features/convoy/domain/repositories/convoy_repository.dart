import '../entities/convoy_snapshot.dart';
import '../entities/journey_ended_event.dart';
import '../entities/participant_arrived_event.dart';
import '../entities/route_updated_event.dart';
import '../../../../core/errors/failure.dart';

/// Abstract repository interface for convoy coordination
/// Defines contracts for real-time position sharing and convoy management
abstract class ConvoyRepository {
  /// Stream of convoy snapshots with real-time member positions
  /// Updates automatically when any member's position changes via RTDB
  Stream<({ConvoySnapshot? snapshot, Failure? failure})> streamConvoyPositions(
    String journeyId,
  );

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
  Future<({ConvoySnapshot? snapshot, Failure? failure})> fetchLatestSnapshot(
    String journeyId,
  );

  /// Stop all convoy coordination activities
  /// Cancels RTDB subscription and stops location publishing
  Future<void> stopCoordination();

  /// Get current connection state to RTDB
  Stream<ConvoyConnectionState> get connectionStateStream;

  /// Server-driven journey termination events.
  /// Fires when the backend emits `journey-ended` for the current journey.
  Stream<JourneyEndedEvent> get journeyEndedStream;

  /// Per-participant arrival events. Fires whenever any participant reaches
  /// the destination; clients use these to update arrival UI and to stop
  /// publishing GPS when [ParticipantArrivedEvent.allArrived] is true.
  Stream<ParticipantArrivedEvent> get participantArrivedStream;

  /// Fires when the backend emits `journey-started` for the current journey.
  /// Members waiting on the home screen should navigate to the map on
  /// receiving this.
  Stream<String> get journeyStartedStream;

  /// Fires (with the current journeyId) when an invited member accepts.
  /// The leader uses this to refresh its participant list live.
  Stream<String> get participantAcceptedStream;

  /// Fires when the leader commits a newer canonical route version.
  Stream<RouteUpdatedEvent> get routeUpdatedStream;

  /// Fires when the backend pushes a `journey-invite` to this user.
  Stream<Map<String, dynamic>> get journeyInviteStream;

  /// Connect and obtain the server's acknowledgement that this client joined
  /// [journeyId]. Used by invited members waiting for the leader to start;
  /// callers must not present a successful listener state until this completes.
  Future<void> joinJourneyRoom(String journeyId);

  /// Connect the socket for user-scoped events (e.g. journey invites) without
  /// joining a journey, and keep it alive across convoy start/stop so the user
  /// keeps receiving invites while on the home screen. Idempotent.
  Future<void> connectUserChannel();

  /// Tear down the user-scoped channel (e.g. on logout).
  Future<void> disconnectUserChannel();

  /// Recover the live WebSocket connection after an app resume.
  ///
  /// The server heartbeat monitor evicts sockets whose client was suspended
  /// (Dart timers freeze in the background), and the client's reconnect
  /// budget may be exhausted by the time the app returns. Forces an
  /// immediate reconnect with a fresh auth token; no-op when already
  /// connected or never connected.
  Future<void> ensureLiveConnection();

  /// Flushes durably queued GPS points through the idempotent backend endpoint.
  Future<void> flushOfflineOutbox();

  /// Release app-scoped retry, polling and stream subscriptions.
  Future<void> dispose();
}
