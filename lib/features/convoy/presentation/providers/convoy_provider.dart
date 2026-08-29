import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show visibleForTesting;
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';

import '../../domain/entities/convoy_snapshot.dart';
import '../../domain/entities/journey_ended_event.dart';
import '../../domain/entities/member_position.dart';
import '../../domain/entities/participant_arrived_event.dart';
import '../../domain/entities/route_updated_event.dart';
import '../../domain/usecases/stream_convoy_positions.dart';
import '../../domain/usecases/publish_my_position.dart';
import '../../domain/usecases/fetch_latest_snapshot.dart';
import '../../domain/repositories/convoy_repository.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/services/location_permission_service.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/services/journey_location_service.dart';

/// Provider for convoy coordination state management
/// Handles real-time position sharing and convoy member tracking
class ConvoyProvider extends ChangeNotifier {
  ConvoyProvider({
    required StreamConvoyPositions streamConvoyPositions,
    required PublishMyPosition publishMyPosition,
    required FetchLatestSnapshot fetchLatestSnapshot,
    required ConvoyRepository repository,
    LocationService? locationService,
    JourneyLocationService? journeyLocationService,
    LocationPermissionGate? permissionGate,
  }) : _streamConvoyPositions = streamConvoyPositions,
       _publishMyPosition = publishMyPosition,
       _fetchLatestSnapshot = fetchLatestSnapshot,
       _repository = repository,
       _journeyLocationService =
           journeyLocationService ??
           JourneyLocationService(
             locationService ?? const GeolocatorLocationService(),
           ),
       _permissionGate =
           permissionGate ?? const DefaultLocationPermissionGate();

  /// Android icon used by geolocator's foreground location service.
  ///
  /// Geolocator defaults to `mipmap/ic_launcher`. TuLink's launcher resource
  /// is named `launcher_icon`, and the plugin's native fallback leaves the
  /// icon id at zero. Android then rejects the foreground notification and
  /// terminates the process as soon as convoy publishing starts.
  @visibleForTesting
  static const AndroidResource androidForegroundNotificationIcon =
      JourneyLocationService.androidForegroundNotificationIcon;

  final StreamConvoyPositions _streamConvoyPositions;
  final PublishMyPosition _publishMyPosition;
  final FetchLatestSnapshot _fetchLatestSnapshot;
  final ConvoyRepository _repository;
  final JourneyLocationService _journeyLocationService;
  final LocationPermissionGate _permissionGate;

  // State
  ConvoySnapshot? _snapshot;
  bool _isPublishing = false;
  bool _isSubscribed = false;

  /// Increments on every room-selection attempt. Async work captures the value
  /// it started under and abandons itself if a newer selection has taken over,
  /// so at most one room is ever owned.
  int _roomGeneration = 0;
  ConvoyConnectionState _connectionState = ConvoyConnectionState.disconnected;
  String? _errorMessage;

  /// The journey we're currently coordinating for, or null if stopped.
  /// Used to prevent dual-journey leaks: starting a new journey without
  /// first stopping the previous one was causing GPS publishes for journey A
  /// while the WebSocket was still subscribed to journey B.
  String? _currentJourneyId;

  /// In-flight guard for [startCoordination]. Multiple call sites
  /// (journey_preview_screen right before navigating to the map, and the map
  /// screen's own _onMapCreated right after) can invoke startCoordination()
  /// for the same journey within milliseconds of each other, unawaited. Without
  /// this guard, a second call arriving while the first is still awaiting the
  /// location permission result would independently call
  /// Geolocator.requestPermission() a second time, stacking two native OS
  /// permission dialogs. Concurrent calls for the same journey now await the
  /// same in-progress Future instead of racing it.
  Future<void>? _coordinationStartFuture;
  String? _coordinationStartJourneyId;

  /// Coalesces duplicate app-resume notifications into one recovery pass.
  Future<void>? _resumeRecoveryFuture;

  /// Tracks consecutive publish failures — used to bail out on a backend
  /// that's permanently refusing publishes (journey ended, auth dead, etc.)
  /// rather than spinning forever.
  int _consecutivePublishFailures = 0;
  static const int _maxConsecutivePublishFailures = 5;

  // GPS and location publishing
  StreamSubscription<Position>? _locationSubscription;
  DateTime? _lastPublishTime;
  Position? _lastKnownPosition;
  bool _publishInFlight = false;

  /// Fixed-cadence beacon timer. Convoy members must keep publishing their
  /// position even while stationary, otherwise they disappear from everyone
  /// else's map. GPS movement events alone are insufficient because a still
  /// device emits nothing.
  Timer? _publishTimer;
  static const Duration _publishInterval = Duration(seconds: 4);

  /// Coalesces rapid snapshot emissions into a single UI notification.
  /// With 2+ moving members, peer `location-update`s arrive several times
  /// per second; notifying listeners on every one triggered a full map
  /// rebuild + marker re-render per emission, saturating the main thread.
  /// We store the freshest snapshot and flush at most once per window.
  Timer? _snapshotNotifyTimer;
  static const Duration _snapshotNotifyInterval = Duration(milliseconds: 300);

  // Journey-scoped listeners are owned as one immutable bundle. Teardown
  // detaches the whole bundle before awaiting cancellation, so a late cancel
  // from room A can never read, null, or cancel room B's replacement fields.
  _RoomSubscriptions? _roomSubscriptions;

  /// User-scoped invite subscription. Lives for the whole session (set up by
  /// [startUserChannel]); deliberately NOT torn down by [stopCoordination],
  /// which is journey-scoped.
  StreamSubscription<Map<String, dynamic>>? _journeyInviteSubscription;

  /// Last journey-ended event received. Surfaced to the UI so screens can
  /// react (toast, navigate away) and clear after handling.
  JourneyEndedEvent? _lastJourneyEndedEvent;
  JourneyEndedEvent? get lastJourneyEndedEvent => _lastJourneyEndedEvent;

  /// Set when the backend emits `journey-started`. Home screen watches this
  /// to auto-navigate members to the map. Cleared by [consumeJourneyStartedEvent].
  String? _pendingJourneyStartedId;
  String? get pendingJourneyStartedId => _pendingJourneyStartedId;

  /// Rolling arrival progress. Updated by the server's `participant-arrived`
  /// events. `_totalMemberCount` here comes from the server payload (the
  /// authoritative count of journey participants) rather than the snapshot's
  /// `members` map, which only contains people whose positions we've seen.
  int _arrivedCount = 0;
  int _totalMemberCount = 0;
  ParticipantArrivedEvent? _lastArrivalEvent;

  int get arrivedCount => _arrivedCount;
  int get totalMemberCount => _totalMemberCount;
  ParticipantArrivedEvent? get lastArrivalEvent => _lastArrivalEvent;

  int _routeUpdatedTick = 0;
  RouteUpdatedEvent? _lastRouteUpdatedEvent;

  /// Monotonic signal and payload for canonical route replacement.
  int get routeUpdatedTick => _routeUpdatedTick;
  RouteUpdatedEvent? get lastRouteUpdatedEvent => _lastRouteUpdatedEvent;

  /// Increments every time an invited member accepts (server `participant-accepted`
  /// event) for the journey we're currently in. Screens showing the participant
  /// list watch this and re-fetch the journey so the leader sees the accepted
  /// state live, without a manual reload.
  int _participantAcceptedTick = 0;
  int get participantAcceptedTick => _participantAcceptedTick;

  /// The journey the most recent `participant-accepted` event belonged to.
  ///
  /// Published alongside the tick so a listener can confirm the burst it is
  /// reacting to is for the journey it is staging, instead of inferring it
  /// from whatever happens to be selected when the refresh finally runs.
  String? _lastParticipantAcceptedJourneyId;
  String? get lastParticipantAcceptedJourneyId =>
      _lastParticipantAcceptedJourneyId;

  /// Increments every time the backend pushes a `journey-invite` to this user
  /// over the WebSocket user channel. The home screen watches this to refresh
  /// the invite list and show a banner without a reload. [lastJourneyInvite]
  /// holds the payload of the most recent invite (journeyName, etc.).
  int _journeyInviteTick = 0;
  int get journeyInviteTick => _journeyInviteTick;
  Map<String, dynamic>? _lastJourneyInvite;
  Map<String, dynamic>? get lastJourneyInvite => _lastJourneyInvite;

  // Dependencies
  final Battery _battery = Battery();

  // Getters
  ConvoySnapshot? get snapshot => _snapshot;
  bool get isPublishing => _isPublishing;
  bool get isSubscribed => _isSubscribed;
  ConvoyConnectionState get connectionState => _connectionState;
  String? get errorMessage => _errorMessage;
  String? get currentJourneyId => _currentJourneyId;

  /// Set when the device could not produce a GPS fix, so this client has joined
  /// the convoy room but is not publishing its own position yet.
  ///
  /// Deliberately separate from [errorMessage]: room membership and location
  /// availability fail independently, and conflating them is what made the UI
  /// claim the socket was "connecting" when the only thing missing was a fix.
  Failure? _locationFailure;
  Failure? get locationFailure => _locationFailure;

  /// True once the convoy room is joined, regardless of whether GPS is working.
  bool get isCoordinating => _isSubscribed;

  /// Monotonic identity of the current connection attempt.
  ///
  /// Owned here rather than by a screen: the attempt lifecycle outlives any
  /// particular widget, so a rebuild (or the retirement of the old map screen)
  /// must not lose or restart it. Consumers use a change in this value as the
  /// signal to begin a fresh bounded connection window.
  int _connectionAttemptId = 0;
  int get connectionAttemptId => _connectionAttemptId;

  /// Begin a new connection attempt. Monotonic for the whole session.
  void _beginConnectionAttempt() {
    _connectionAttemptId++;
  }

  void _setLocationFailure(Failure? failure) {
    if (_locationFailure == failure) return;
    _locationFailure = failure;
    notifyListeners();
  }

  /// Re-establish the convoy connection for [journeyId] without recreating the
  /// journey.
  ///
  /// Recovers the socket and room membership only; GPS publishing is recovered
  /// separately by [retryLocationPublishing], because the two fail for
  /// different reasons. Safe to call while already connected.
  Future<void> reconnect(String journeyId) async {
    _clearError();
    // An explicit reconnect is a new attempt even for the same journey.
    _beginConnectionAttempt();
    notifyListeners();
    try {
      // Bring the socket back up (fresh token) before re-subscribing.
      await _repository.ensureLiveConnection();

      // Re-subscribe only if this journey lost its streams; an existing healthy
      // subscription is left alone so we don't churn a working connection.
      if (_currentJourneyId != journeyId || !_isSubscribed) {
        await stopCoordination();
        await startCoordination(journeyId);
        return;
      }

      await _repository.joinJourneyRoom(journeyId);
    } catch (e) {
      _setError(e is Failure ? e.message : 'Could not reconnect to the convoy');
    }
  }

  /// Retry location acquisition for the journey already being coordinated,
  /// without tearing down or recreating the room membership. Safe to call from
  /// a UI retry affordance.
  Future<bool> retryLocationPublishing() async {
    final journeyId = _currentJourneyId;
    if (journeyId == null) return false;

    // The pipeline may already be running but starved of a fix. Ask for a
    // fresh one rather than reporting success off a stale flag.
    if (_isPublishing) {
      final position = await _journeyLocationService.refreshPosition();
      if (_currentJourneyId != journeyId) return false;
      if (position == null) {
        _setLocationFailure(ConvoyFailure.locationUnavailable);
        return false;
      }
      await _handleLocationUpdate(journeyId, position);
      return _locationFailure == null;
    }

    // Pipeline is down — rebuild it, replacing any half-built subscription.
    await _locationSubscription?.cancel();
    _locationSubscription = null;
    await _journeyLocationService.stop(journeyId: journeyId);
    _publishTimer?.cancel();
    _publishTimer = null;

    await _startLocationPublishing(journeyId);
    return _isPublishing && _locationFailure == null;
  }

  /// Called when the app returns to the foreground.
  ///
  /// Reconnects the transport, confirms room membership, and replaces the
  /// retained snapshot with the server's latest positions. Reconnecting alone
  /// cannot recover broadcasts missed while Dart was suspended, which left
  /// peer markers frozen at their pre-background coordinates.
  Future<void> onAppResumed() {
    final existing = _resumeRecoveryFuture;
    if (existing != null) return existing;

    final recovery = _recoverAfterResume();
    _resumeRecoveryFuture = recovery;
    return recovery.whenComplete(() {
      if (identical(_resumeRecoveryFuture, recovery)) {
        _resumeRecoveryFuture = null;
      }
    });
  }

  Future<void> _recoverAfterResume() async {
    await _repository.ensureLiveConnection();

    final journeyId = _currentJourneyId;
    if (journeyId == null || !_isSubscribed) return;

    try {
      await _repository.joinJourneyRoom(journeyId);
      final result = await _fetchLatestSnapshot(journeyId);

      // A journey switch or stop may complete while recovery is in flight.
      // Never apply an old room's snapshot to the new active journey.
      if (_currentJourneyId != journeyId || !_isSubscribed) return;

      final freshSnapshot = result.snapshot;
      if (freshSnapshot != null && freshSnapshot.journeyId == journeyId) {
        _snapshot = _mergeResumeSnapshot(freshSnapshot, _snapshot);
        _clearError();
        notifyListeners();
      }
    } catch (error) {
      // Keep the retained snapshot visible. The live stream can still recover
      // after a transient REST or room-join failure.
      debugPrint('Convoy resume recovery failed: $error');
    }
  }

  /// Keeps socket positions received during the REST request when they are
  /// newer than the corresponding rehydrated member. Members absent from the
  /// server response stay absent so a participant removed while suspended is
  /// not resurrected from retained client state.
  ConvoySnapshot _mergeResumeSnapshot(
    ConvoySnapshot serverSnapshot,
    ConvoySnapshot? retainedSnapshot,
  ) {
    if (retainedSnapshot == null ||
        retainedSnapshot.journeyId != serverSnapshot.journeyId) {
      return serverSnapshot;
    }

    final members = Map<String, MemberPosition>.from(serverSnapshot.members);
    for (final entry in members.entries.toList(growable: false)) {
      final retained = retainedSnapshot.members[entry.key];
      if (retained != null && retained.timestamp > entry.value.timestamp) {
        members[entry.key] = retained;
      }
    }
    return serverSnapshot.copyWith(members: members);
  }

  /// Start convoy coordination for a journey.
  /// Begins both GPS publishing and real-time position streaming.
  ///
  /// Idempotent: if we're already coordinating the same journey, this is a
  /// no-op. If we're coordinating a *different* journey, that one is stopped
  /// first to avoid leaking subscriptions / GPS streams across journeys.
  ///
  /// Concurrency-safe: multiple call sites can invoke this for the same
  /// journey within one navigation transition. A second call for the same
  /// journey while the first is starting awaits the same in-flight future
  /// instead of independently requesting native permissions again.
  Future<void> startCoordination(String journeyId) async {
    // Already fully coordinating (subscribed + publishing GPS) — nothing to do.
    if (_currentJourneyId == journeyId && _isSubscribed && _isPublishing) {
      return;
    }

    // Already starting coordination for this journey — join the in-flight
    // call rather than racing it.
    if (_coordinationStartJourneyId == journeyId &&
        _coordinationStartFuture != null) {
      return _coordinationStartFuture;
    }

    // Switching journeys — tear down the previous one cleanly.
    if (_currentJourneyId != null && _currentJourneyId != journeyId) {
      print(
        '🔀 ConvoyProvider: switching from $_currentJourneyId to $journeyId, '
        'stopping previous coordination first',
      );
      await stopCoordination();
    }

    _coordinationStartJourneyId = journeyId;
    final startFuture = _startCoordinationInternal(journeyId);
    _coordinationStartFuture = startFuture;
    try {
      await startFuture;
    } finally {
      // Only clear if we're still the owning in-flight call — a subsequent
      // startCoordination() for a different journey may have already
      // replaced these fields.
      if (_coordinationStartJourneyId == journeyId) {
        _coordinationStartFuture = null;
        _coordinationStartJourneyId = null;
      }
    }
  }

  Future<void> _startCoordinationInternal(String journeyId) async {
    // Same single-room ownership rule as joinJourneyRoom: going live in B must
    // release A first, or A's subscriptions keep delivering into B's session.
    final generation = ++_roomGeneration;
    if (_currentJourneyId != null && _currentJourneyId != journeyId) {
      await _releaseRoomState();
      if (generation != _roomGeneration) return;
    }

    try {
      _clearError();
      _setLocationFailure(null);
      _currentJourneyId = journeyId;
      // Joining a journey is a new connection attempt.
      _beginConnectionAttempt();

      // 1. Join and subscribe FIRST. Room membership and the journey snapshot
      //    depend on neither a permission grant nor a GPS fix. The OS
      //    permission dialog can stay open indefinitely, so awaiting it here
      //    delayed the snapshot by exactly as long as the user hesitated.
      if (!_isSubscribed) {
        await _startConvoyStream(journeyId, generation);
        if (generation != _roomGeneration) return;
      }
      _isSubscribed = true;
      notifyListeners();

      // 2. Permission is then requested independently of membership.
      //
      // Everything from here on is location work, and it runs in its own
      // try/catch so that a throwing permission gate cannot fall through to the
      // outer handler — that one nulls _currentJourneyId, which would leave the
      // provider subscribed to a room it no longer believes it is in.
      try {
        final permissionResult = await _permissionGate.request();

        // The journey may have been switched or stopped while the dialog was
        // open; a late grant must not start publishing for the wrong room.
        if (_currentJourneyId != journeyId || generation != _roomGeneration) {
          return;
        }

        // Location problems are reported on their own channel so the UI can say
        // "we can't see your location" without implying the convoy is
        // unreachable, and without tearing down convoy membership.
        if (!permissionResult.granted) {
          _setLocationFailure(
            permissionResult.failure ?? ConvoyFailure.locationPermissionDenied,
          );
          return;
        }

        // 3. Bounded; can fail without invalidating the room join.
        await _startLocationPublishing(journeyId);
      } catch (e) {
        if (_currentJourneyId != journeyId) return;
        // A location-side failure, not a convoy failure: membership stands.
        _setLocationFailure(
          e is Failure
              ? e
              : ConvoyFailure(
                  message: 'Could not access your location',
                  details: e.toString(),
                  timestamp: DateTime.now(),
                  isRetryable: true,
                ),
        );
      }
    } catch (e) {
      print('❌ Failed to start convoy coordination: $e');
      _currentJourneyId = null;
      final failure = e is Failure
          ? e
          : ConvoyFailure(
              message: 'Failed to start convoy coordination',
              details: 'An unexpected error occurred: $e',
              timestamp: DateTime.now(),
            );
      _setError(failure.message);
    }
  }

  /// Open the user-scoped WebSocket channel so the user receives `journey-invite`
  /// pushes live (e.g. while sitting on the home screen). Connects the socket
  /// and keeps it alive across convoy start/stop. Idempotent — call once after
  /// login. FCM covers the case where the app is backgrounded/closed.
  Future<void> startUserChannel() async {
    try {
      await _repository.connectUserChannel();

      _journeyInviteSubscription ??= _repository.journeyInviteStream.listen(
        (invite) {
          print('📨 ConvoyProvider: journey-invite $invite');
          _lastJourneyInvite = invite;
          _journeyInviteTick++;
          notifyListeners();
        },
        onError: (Object error) {
          print('❌ journey-invite stream error: $error');
        },
      );
    } catch (e) {
      print('❌ Failed to start user channel: $e');
    }
  }

  /// Close the user-scoped channel (call on logout). Cancels the invite
  /// subscription and drops the socket if no journey is using it.
  Future<void> stopUserChannel() async {
    await _journeyInviteSubscription?.cancel();
    _journeyInviteSubscription = null;
    await _repository.disconnectUserChannel();
  }

  /// Join a journey room to receive real-time events without starting GPS.
  /// Used by members waiting on the home screen for the leader to start.
  Future<bool> joinJourneyRoom(String journeyId) async {
    // A confirmed same-room owner is a true no-op. Invalidating its generation
    // here would leave every installed callback alive but permanently muted.
    if (_currentJourneyId == journeyId && _isSubscribed) return true;

    // A user is in at most one convoy room. Claim ownership of the handoff with
    // a generation token *before anything else* — including the already-joined
    // shortcut. Claiming it after that check let two joins that both started
    // while `_currentJourneyId`/`_isSubscribed` were still unset run
    // concurrently all the way into the repository.
    final generation = ++_roomGeneration;

    // Tear the previous room down completely — subscriptions included — before
    // joining the new one. Overwriting `_currentJourneyId` while room A's
    // snapshot, connection, journey-ended, journey-started, arrival and
    // participant subscriptions were still live meant A's events arrived and
    // were attributed to B.
    if (_currentJourneyId != null || _isSubscribed) {
      await _releaseRoomState();
      if (generation != _roomGeneration) return false;
    }

    try {
      _clearError();

      // Do not mark listener mode ready until the server confirms room
      // membership. The repository serialises the handoff and only resolves
      // once the server's ack names *this* journey.
      await _repository.joinJourneyRoom(journeyId);

      // A newer join took over while the server was answering: that room owns
      // the session now, so this one must not install its streams or id.
      if (generation != _roomGeneration) {
        print('↩️ ConvoyProvider: discarding stale room join $journeyId');
        return false;
      }

      // Only now is the room safely ours.
      _currentJourneyId = journeyId;
      final installed = await _startConvoyStream(journeyId, generation);
      if (!installed) return false;

      _isSubscribed = true;
      notifyListeners();
      print('✅ ConvoyProvider: joined journey room $journeyId (listener mode)');
      return true;
    } catch (e) {
      print('❌ ConvoyProvider: failed to join room: $e');
      if (generation == _roomGeneration) {
        // A failed join must leave a deterministic recoverable state, never a
        // mixed A/B one: nothing of this attempt survives, and nothing of the
        // previous room does either.
        await _cancelRoomSubscriptions();
        _currentJourneyId = null;
        _isSubscribed = false;
        _setError('Live updates are reconnecting');
        notifyListeners();
      }
      return false;
    }
  }

  /// Stop convoy coordination
  /// Cancels GPS publishing and real-time streaming
  Future<void> stopCoordination({bool invalidateRoomOwner = true}) async {
    print('🛑 ConvoyProvider: Stopping coordination...');
    final journeyId = _currentJourneyId;

    // Explicit stops supersede any start/cancel/install work already awaiting
    // an async boundary. A handoff has already claimed its newer generation,
    // so its internal release opts out below and preserves that owner.
    if (invalidateRoomOwner) ++_roomGeneration;

    // Stop location publishing
    await _locationSubscription?.cancel();
    _locationSubscription = null;
    await _journeyLocationService.stop(journeyId: journeyId);
    _isPublishing = false;

    // Stop the fixed-cadence beacon timer
    _publishTimer?.cancel();
    _publishTimer = null;

    // Stop every journey-scoped subscription in one place, so a room handoff
    // and a full stop can never disagree about what was cancelled.
    await _cancelRoomSubscriptions();

    // Stop the repository coordination (WebSocket, etc.)
    try {
      await _repository.stopCoordination();
      print('✅ ConvoyProvider: Repository coordination stopped');
    } catch (e) {
      print('⚠️ ConvoyProvider: Failed to stop repository coordination: $e');
    }

    _isSubscribed = false;

    // Reset state
    _snapshot = null;
    _connectionState = ConvoyConnectionState.disconnected;
    _lastPublishTime = null;
    _lastKnownPosition = null;
    _currentJourneyId = null;
    _consecutivePublishFailures = 0;
    _arrivedCount = 0;
    _totalMemberCount = 0;
    _lastArrivalEvent = null;
    _locationFailure = null;
    _clearError();

    print('✅ ConvoyProvider: Coordination stopped completely');
    notifyListeners();
  }

  /// Start GPS location publishing with throttling
  Future<void> _startLocationPublishing(String journeyId) async {
    try {
      await _locationSubscription?.cancel();
      _locationSubscription = _journeyLocationService.positions.listen(
        (Position position) => _handleLocationUpdate(journeyId, position),
        onError: (Object error) {
          _setLocationFailure(
            ConvoyFailure(
              message: 'Location updates stopped',
              details: error.toString(),
              timestamp: DateTime.now(),
              isRetryable: true,
            ),
          );
        },
      );

      // Seed an initial position so we beacon before the first movement event
      // arrives (a still device emits nothing on its own). Bounded by
      // [LocationService]: a device that cannot produce a fix yields null
      // rather than hanging this method — and therefore the whole coordination
      // start — forever.
      final initial = await _journeyLocationService.start(journeyId);

      // The journey may have been switched or stopped while we waited for the
      // fix; a late position must never publish against the wrong room.
      if (_currentJourneyId != journeyId) return;

      if (initial != null) {
        _lastKnownPosition = initial;
        // A fix was obtained — clear any failure left over from an earlier
        // attempt so a successful retry is reported as recovered.
        _setLocationFailure(null);
        await _publishLocation(journeyId, initial, false);
        if (_currentJourneyId != journeyId) return;
        _journeyLocationService.broadcastLatest();
      } else {
        _setLocationFailure(ConvoyFailure.locationUnavailable);
      }

      // Fixed-cadence beacon: republish the last known position on a steady
      // interval even while stationary, so parked / just-joined members stay
      // visible to the rest of the convoy. Refreshing first is important for
      // arrival detection: the cached position may still carry the speed and
      // timestamp from the last moving GPS tick.
      _publishTimer?.cancel();
      _publishTimer = Timer.periodic(_publishInterval, (_) {
        unawaited(_publishBeacon(journeyId));
      });

      _isPublishing = true;
      notifyListeners();
    } catch (e) {
      // The publishing pipeline could not be established. Room membership is
      // unaffected, so report this on the location channel rather than
      // failing coordination outright.
      _isPublishing = false;
      _setLocationFailure(ConvoyFailure.locationServiceDisabled);
    }
  }

  /// Publish a fresh stationary beacon when possible.
  ///
  /// The backend only marks a participant arrived when the point is near the
  /// destination and the reported speed is low. Replaying the previous moving
  /// [Position] forever can therefore prevent an arrival event after the
  /// driver parks before the platform emits another stream tick.
  Future<void> _publishBeacon(String journeyId) async {
    if (_currentJourneyId != journeyId) return;

    final fresh = await _journeyLocationService.refreshPosition(
      timeout: const Duration(seconds: 3),
    );
    if (_currentJourneyId != journeyId) return;

    final position = fresh ?? _lastKnownPosition;
    if (position == null) return;
    if (fresh != null) _lastKnownPosition = fresh;

    await _publishLocation(journeyId, position, position.speed > 0.5);
  }

  /// Handle a new GPS location from the movement stream. Caches the position
  /// for the periodic beacon and publishes immediately (throttled to 1/sec)
  /// for responsive live tracking while moving.
  Future<void> _handleLocationUpdate(
    String journeyId,
    Position position,
  ) async {
    // A stream tick for a journey we have since left must not publish.
    if (_currentJourneyId != journeyId) return;

    _lastKnownPosition = position;

    // A fix arrived after a cold start — publishing can resume without the
    // journey being recreated.
    if (_locationFailure != null) _setLocationFailure(null);

    final now = DateTime.now();
    final isMoving = position.speed > 0.5; // Moving if speed > 0.5 m/s

    // Throttle movement-driven publishes to max 1/sec; the periodic beacon
    // guarantees a baseline cadence regardless of movement.
    if (_shouldThrottleUpdate(now, isMoving)) {
      return;
    }

    await _publishLocation(journeyId, position, isMoving);
  }

  /// Check if update should be throttled (max 1 per second)
  bool _shouldThrottleUpdate(DateTime now, bool isMoving) {
    if (_lastPublishTime == null) return false;

    final timeSinceLastPublish = now.difference(_lastPublishTime!);
    return timeSinceLastPublish.inMilliseconds < 1000; // Max 1 per second
  }

  /// Publish location to backend.
  ///
  /// Bails out (calls [stopCoordination]) on terminal failures:
  ///  - Journey is no longer active (backend rejects publish)
  ///  - Auth is dead (user is no longer authorized for this journey)
  ///
  /// Transient failures (network, rate limit) are logged and retried on the
  /// next GPS tick.
  Future<void> _publishLocation(
    String journeyId,
    Position position,
    bool isMoving,
  ) async {
    // Guard against stale callbacks after stopCoordination.
    if (_currentJourneyId != journeyId || _publishInFlight) return;
    _publishInFlight = true;

    try {
      // Get battery level
      int? batteryLevel;
      try {
        batteryLevel = await _battery.batteryLevel;
      } catch (e) {
        // Battery info not available, continue without it
      }

      final result = await _publishMyPosition(
        journeyId: journeyId,
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: position.timestamp.millisecondsSinceEpoch,
        accuracy: position.accuracy,
        altitude: position.altitude,
        heading: position.heading,
        speed: position.speed,
        batteryLevel: batteryLevel,
        isMoving: isMoving,
      );

      if (result.success) {
        _lastPublishTime = DateTime.now();
        _consecutivePublishFailures = 0;
        _clearError();
        return;
      }

      // We got a structured failure — decide whether to bail or keep trying.
      await _handlePublishFailure(journeyId, result.failure);
    } catch (e) {
      // Unexpected (shouldn't happen — repository normalizes errors), but
      // count it so a sustained crash loop still trips the circuit breaker.
      print('⚠️ Location publish error: $e');
      await _handlePublishFailure(
        journeyId,
        e is Failure
            ? e
            : ConvoyFailure(
                message: 'Location publish failed',
                details: e.toString(),
                timestamp: DateTime.now(),
              ),
      );
    } finally {
      _publishInFlight = false;
    }
  }

  /// Decide whether a publish failure is terminal (stop) or transient (retry).
  Future<void> _handlePublishFailure(String journeyId, Failure? failure) async {
    if (failure == null) return;

    if (_isJourneyTerminalFailure(failure)) {
      print('🏁 Terminal journey state confirmed — reconciling completion');
      if (_lastJourneyEndedEvent?.journeyId != journeyId) {
        _lastJourneyEndedEvent = JourneyEndedEvent(
          journeyId: journeyId,
          reason: 'terminal-reconciliation',
          endedAt: DateTime.now(),
        );
      }
      await stopCoordination();
      notifyListeners();
      return;
    }

    if (_isTerminalPublishFailure(failure)) {
      print(
        '🛑 Terminal publish failure (${failure.message}) — stopping coordination',
      );
      _setError(failure.message);
      await stopCoordination();
      return;
    }

    _consecutivePublishFailures++;
    print(
      '⚠️ Transient publish failure ($_consecutivePublishFailures/$_maxConsecutivePublishFailures): '
      '${failure.message}',
    );

    if (_consecutivePublishFailures >= _maxConsecutivePublishFailures) {
      print(
        '⚠️ Publish failures sustained — keeping coordination alive for recovery',
      );
      _setError('Connection lost. Reconnecting…');
      // A mobile handoff or background radio suspension can easily last five
      // publish intervals. Stopping here permanently removed this user from
      // peers even after connectivity returned. Keep the guarded beacon loop
      // alive; its next success clears the error and resets the counter.
      _consecutivePublishFailures = _maxConsecutivePublishFailures;
    }
  }

  /// Terminal failures the backend signals as "stop, this is expected" —
  /// no toast, no error banner, just stop the publish loop and clear state.
  bool _isSilentTerminalFailure(Failure failure) {
    return failure is ConvoyFailure && failure == ConvoyFailure.stopPolling;
  }

  bool _isJourneyTerminalFailure(Failure failure) {
    return failure is ConvoyFailure &&
        (failure == ConvoyFailure.journeyNotActive ||
            _isSilentTerminalFailure(failure));
  }

  /// Whether a failure means the journey/auth is gone for good and we should
  /// stop the publish loop entirely (vs. a transient network blip).
  bool _isTerminalPublishFailure(Failure failure) {
    if (failure is ConvoyFailure) {
      return failure == ConvoyFailure.journeyNotActive ||
          failure == ConvoyFailure.notJourneyMember ||
          failure.message.toLowerCase().contains('not active') ||
          failure.message.toLowerCase().contains('not authorized') ||
          failure.message.toLowerCase().contains('not a member');
    }
    if (failure is AuthFailure || failure is TokenFailure) {
      return true;
    }
    if (failure is ServerFailure) {
      final code = failure.statusCode ?? 0;
      return code == 401 || code == 403;
    }
    return false;
  }

  /// Cancel every journey-scoped subscription without touching room identity.
  ///
  /// Separated from [stopCoordination] so a superseded join can clean up its
  /// own streams without also tearing down the room that replaced it.
  Future<void> _cancelRoomSubscriptions() async {
    final subscriptions = _roomSubscriptions;
    _roomSubscriptions = null;
    _snapshotNotifyTimer?.cancel();
    _snapshotNotifyTimer = null;
    _pendingJourneyStartedId = null;
    await subscriptions?.cancel();
  }

  /// Release the room currently held, ahead of claiming a different one.
  ///
  /// Identical to [stopCoordination] except that it is used *inside* a handoff,
  /// where the caller has already claimed the newer generation.
  Future<void> _releaseRoomState() =>
      stopCoordination(invalidateRoomOwner: false);

  /// Start streaming convoy positions and connection state.
  ///
  /// [generation] is the room-ownership token this subscription set belongs
  /// to. Every callback re-checks it, so a stream installed by a superseded
  /// attempt can never deliver into the room that replaced it — checking only
  /// `_currentJourneyId` was not enough, because a re-entry into the *same*
  /// journey produces the same id with a different owner.
  Future<bool> _startConvoyStream(String journeyId, int generation) async {
    await _cancelRoomSubscriptions();

    /// True while this subscription set still owns the room.
    bool owns() =>
        generation == _roomGeneration && _currentJourneyId == journeyId;

    if (!owns()) return false;

    var terminalHandled = false;

    // Listen to convoy position updates
    final convoySubscription = _streamConvoyPositions(journeyId).listen(
      (result) {
        if (!owns()) return;
        if (result.snapshot != null) {
          _snapshot = result.snapshot;
          _clearError();
          // Coalesce high-frequency snapshot updates: store the latest
          // snapshot now, but flush to the UI at most once per window so
          // N rapid peer updates collapse into one render.
          _scheduleSnapshotNotify();
        } else if (result.failure != null) {
          _setError(result.failure!.message);
          notifyListeners();
        }
      },
      onError: (error) {
        print('❌ Convoy stream error: $error');
        final failure = error is Failure
            ? error
            : ConvoyFailure.rtdbConnectionFailed;
        _setError(failure.message);
        notifyListeners();
      },
    );

    // Listen to WebSocket connection state changes
    final connectionSubscription = _repository.connectionStateStream.listen(
      (connectionState) {
        if (!owns()) return;
        // An automatic reconnect is a new attempt too, so consumers restart
        // their bounded window rather than inheriting the previous timeout.
        if (connectionState == ConvoyConnectionState.reconnecting &&
            _connectionState != ConvoyConnectionState.reconnecting) {
          _beginConnectionAttempt();
        }
        _connectionState = connectionState;
        notifyListeners();
      },
      onError: (error) {
        print('❌ Connection state error: $error');
        _connectionState = ConvoyConnectionState.error;
        notifyListeners();
      },
    );

    // Listen for server-driven journey-ended events. When the backend ends
    // a journey it emits this; we must stop coordinating that journey so we
    // don't keep hammering the now-invalid room.
    final journeyEndedSubscription = _repository.journeyEndedStream.listen(
      (event) async {
        // Identity is the event's own; ownership is this subscription's.
        // A late end for A must not tear down B, and an end delivered to a
        // superseded subscription must not act at all.
        if (!owns() || event.journeyId != journeyId || terminalHandled) return;
        terminalHandled = true;

        print(
          '🏁 ConvoyProvider: journey-ended received for ${event.journeyId}',
        );
        _lastJourneyEndedEvent = event;
        _setError('Journey ended');
        await stopCoordination();
        notifyListeners();
      },
      onError: (error) {
        print('❌ journey-ended stream error: $error');
      },
    );

    // Per-participant arrival updates. On allArrived we stop publishing GPS
    // immediately — the backend auto-completes the journey and the
    // journey-ended subscription above handles the navigation/teardown.
    final participantArrivedSubscription = _repository.participantArrivedStream
        .listen(
          (event) async {
            if (!owns()) return;
            _arrivedCount = event.arrivedCount;
            _totalMemberCount = event.totalCount;
            _lastArrivalEvent = event;

            if (event.allArrived) {
              print(
                '🏁 ConvoyProvider: all participants arrived — stopping publishing',
              );
              await _stopLocationPublishing(journeyId);
            }

            notifyListeners();
          },
          onError: (Object error) {
            print('❌ participant-arrived stream error: $error');
          },
        );

    final journeyStartedSubscription = _repository.journeyStartedStream.listen(
      (eventJourneyId) {
        // The event carries its own identity (parsed from the payload by the
        // data source). It is accepted only for the room this subscription set
        // owns — a start broadcast for A must never activate B.
        if (!owns() || eventJourneyId != journeyId) return;
        print('🚀 ConvoyProvider: journey-started for $eventJourneyId');
        _pendingJourneyStartedId = eventJourneyId;
        notifyListeners();
      },
      onError: (Object error) {
        print('❌ journey-started stream error: $error');
      },
    );

    final participantAcceptedSubscription = _repository
        .participantAcceptedStream
        .listen(
          (eventJourneyId) {
            // Journey-scoped from the payload — see the data source. A late
            // acceptance for A must not refresh B's roster.
            if (!owns() || eventJourneyId != journeyId) return;
            print(
              '🤝 ConvoyProvider: participant-accepted for $eventJourneyId',
            );
            _lastParticipantAcceptedJourneyId = eventJourneyId;
            _participantAcceptedTick++;
            notifyListeners();
          },
          onError: (Object error) {
            print('❌ participant-accepted stream error: $error');
          },
        );

    final routeUpdatedSubscription = _repository.routeUpdatedStream.listen(
      (event) {
        if (!owns() || event.journeyId != journeyId) return;
        final previousVersion =
            _lastRouteUpdatedEvent?.journeyId == event.journeyId
            ? _lastRouteUpdatedEvent!.routeVersion
            : 0;
        if (event.routeVersion <= previousVersion) return;
        _lastRouteUpdatedEvent = event;
        _routeUpdatedTick++;
        notifyListeners();
      },
      onError: (Object error) {
        print('❌ route-updated stream error: $error');
      },
    );

    _roomSubscriptions = _RoomSubscriptions(
      convoy: convoySubscription,
      connection: connectionSubscription,
      journeyEnded: journeyEndedSubscription,
      participantArrived: participantArrivedSubscription,
      journeyStarted: journeyStartedSubscription,
      participantAccepted: participantAcceptedSubscription,
      routeUpdated: routeUpdatedSubscription,
    );
    return true;
  }

  /// Schedule a coalesced `notifyListeners()` for snapshot updates. If a
  /// flush is already pending, this is a no-op — the latest `_snapshot` is
  /// already captured and will be delivered when the window elapses. This
  /// collapses bursts of peer location-updates into one render per window.
  void _scheduleSnapshotNotify() {
    if (_snapshotNotifyTimer != null) return;
    _snapshotNotifyTimer = Timer(_snapshotNotifyInterval, () {
      _snapshotNotifyTimer = null;
      notifyListeners();
    });
  }

  /// Stops just the GPS publishing side (location stream + heartbeat) while
  /// leaving snapshot/connection subscriptions intact. Used when the backend
  /// signals allArrived: we want to silence the publish loop but stay in the
  /// room long enough to receive the journey-ended event that follows.
  Future<void> _stopLocationPublishing(String journeyId) async {
    await _locationSubscription?.cancel();
    _locationSubscription = null;
    await _journeyLocationService.stop(journeyId: journeyId);
    _isPublishing = false;

    _publishTimer?.cancel();
    _publishTimer = null;
  }

  /// Consume the last arrival event after the UI has reacted (toast,
  /// notification). Prevents the same event from being acted on twice.
  void consumeArrivalEvent() {
    _lastArrivalEvent = null;
    notifyListeners();
  }

  /// Consume the last journey-ended event. The UI calls this after it has
  /// reacted (shown a toast, navigated) so the same event isn't acted on twice.
  void consumeJourneyEndedEvent() {
    _lastJourneyEndedEvent = null;
    notifyListeners();
  }

  /// Consume the pending journey-started event after the UI has navigated.
  void consumeJourneyStartedEvent() {
    _pendingJourneyStartedId = null;
    notifyListeners();
  }

  /// Fetch latest snapshot manually (for refresh)
  Future<void> refreshSnapshot(String journeyId) async {
    try {
      final result = await _fetchLatestSnapshot(journeyId);
      if (result.snapshot != null) {
        _snapshot = result.snapshot;
        _clearError();
      } else if (result.failure != null) {
        _setError(result.failure!.message);
      }
      notifyListeners();
    } catch (e) {
      print('❌ Failed to refresh snapshot: $e');
      _setError('Failed to refresh convoy data');
    }
  }

  /// Get convoy snapshot for display (excludes current user from markers)
  ConvoySnapshot? getDisplaySnapshot(String currentUserId) {
    if (_snapshot == null) return null;

    // Mapbox built-in location component shows the user's own position,
    // so we exclude them from the convoy markers to avoid a duplicate dot.
    return _snapshot!.filterOutUser(currentUserId);
  }

  /// Get convoy snapshot for member counting (includes current user)
  ConvoySnapshot? getFullSnapshot() {
    return _snapshot;
  }

  void _setError(String message) {
    _errorMessage = message;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Clear error manually
  void clearError() {
    _clearError();
  }

  /// Set snapshot for testing purposes only
  @visibleForTesting
  void setSnapshotForTesting(ConvoySnapshot snapshot) {
    _snapshot = snapshot;
    notifyListeners();
  }

  @override
  void dispose() {
    stopCoordination();
    super.dispose();
  }
}

class _RoomSubscriptions {
  const _RoomSubscriptions({
    required this.convoy,
    required this.connection,
    required this.journeyEnded,
    required this.participantArrived,
    required this.journeyStarted,
    required this.participantAccepted,
    required this.routeUpdated,
  });

  final StreamSubscription<({ConvoySnapshot? snapshot, Failure? failure})>
  convoy;
  final StreamSubscription<ConvoyConnectionState> connection;
  final StreamSubscription<JourneyEndedEvent> journeyEnded;
  final StreamSubscription<ParticipantArrivedEvent> participantArrived;
  final StreamSubscription<String> journeyStarted;
  final StreamSubscription<String> participantAccepted;
  final StreamSubscription<RouteUpdatedEvent> routeUpdated;

  Future<void> cancel() => Future.wait<void>([
    convoy.cancel(),
    connection.cancel(),
    journeyEnded.cancel(),
    participantArrived.cancel(),
    journeyStarted.cancel(),
    participantAccepted.cancel(),
    routeUpdated.cancel(),
  ]);
}
