import 'dart:async';
import 'dart:io' show Platform;

import 'package:geolocator/geolocator.dart';

import 'package:tulink_flutter/core/services/location_service.dart';

/// Owns the single native location session for an active journey.
///
/// Convoy publishing, navigation and map presentation subscribe to the same
/// broadcast stream. Consumers may detach independently; only the journey
/// lifecycle starts or stops the underlying platform stream.
class JourneyLocationService {
  /// Creates a journey-scoped owner over bounded platform location access.
  JourneyLocationService(this._locationService);

  /// Android notification icon used by the foreground location service.
  static const AndroidResource androidForegroundNotificationIcon =
      AndroidResource(name: 'launcher_icon', defType: 'mipmap');

  final LocationService _locationService;
  final StreamController<Position> _positions =
      StreamController<Position>.broadcast(sync: true);

  StreamSubscription<Position>? _nativeSubscription;
  String? _journeyId;
  Position? _latestPosition;
  int _generation = 0;

  /// Shared position stream for convoy, navigation and map consumers.
  Stream<Position> get positions => _positions.stream;

  /// Most recent position received during the active journey.
  Position? get latestPosition => _latestPosition;

  /// Journey that currently owns the native location session.
  String? get journeyId => _journeyId;

  /// Whether the platform position stream is subscribed.
  bool get isRunning => _nativeSubscription != null;

  /// Starts or reuses the native session for [journeyId].
  Future<Position?> start(String journeyId) async {
    if (_journeyId == journeyId && _nativeSubscription != null) {
      return _latestPosition;
    }

    final generation = ++_generation;
    await _nativeSubscription?.cancel();
    _nativeSubscription = null;
    _journeyId = journeyId;
    _latestPosition = null;

    // Attach the continuous native session before asking for a one-shot fix.
    // A cold GPS lookup can take several seconds; making the stream wait behind
    // it delayed the first real moving fix and made journey startup appear
    // frozen even though the platform was already capable of tracking.
    _nativeSubscription = _locationService
        .getPositionStream(locationSettings: buildLocationSettings())
        .listen(
          (position) {
            if (generation != _generation || _journeyId != journeyId) return;
            _emit(position);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (generation != _generation || _journeyId != journeyId) return;
            _positions.addError(error, stackTrace);
          },
        );

    final initial = await _locationService.getCurrentPosition();
    if (generation != _generation || _journeyId != journeyId) return null;
    if (initial != null) {
      final held = _latestPosition;
      if (held == null || !initial.timestamp.isBefore(held.timestamp)) {
        _latestPosition = initial;
      }
    }

    return _latestPosition;
  }

  /// Replays the held fix after the journey owner has completed its own
  /// awaited startup work. This keeps start deterministic while still seeding
  /// consumers that subscribed before the native session became available.
  void broadcastLatest() {
    final position = _latestPosition;
    if (_journeyId != null && position != null) _positions.add(position);
  }

  /// Requests a bounded fresh fix without creating another native stream.
  Future<Position?> refreshPosition({
    Duration? timeout,
    bool broadcast = false,
  }) async {
    final journeyId = _journeyId;
    final generation = _generation;
    if (journeyId == null) return null;
    final position = await _locationService.getCurrentPosition(
      timeout: timeout,
    );
    if (generation != _generation ||
        _journeyId != journeyId ||
        position == null) {
      return null;
    }
    _latestPosition = position;
    if (broadcast) _positions.add(position);
    return position;
  }

  /// Stops the native session when [journeyId] still owns it.
  Future<void> stop({String? journeyId}) async {
    if (journeyId != null && _journeyId != journeyId) return;
    ++_generation;
    await _nativeSubscription?.cancel();
    _nativeSubscription = null;
    _journeyId = null;
    _latestPosition = null;
  }

  /// Releases both the native session and the shared broadcast controller.
  Future<void> dispose() async {
    await stop();
    await _positions.close();
  }

  void _emit(Position position) {
    _latestPosition = position;
    _positions.add(position);
  }

  /// Platform configuration required for screen-off journey tracking.
  static LocationSettings buildLocationSettings() {
    const accuracy = LocationAccuracy.bestForNavigation;
    const distanceFilter = 5;

    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        forceLocationManager: false,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Journey in progress',
          notificationText:
              'Tu-Link is sharing your location with your convoy.',
          notificationIcon: androidForegroundNotificationIcon,
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }

    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        activityType: ActivityType.automotiveNavigation,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
        pauseLocationUpdatesAutomatically: false,
      );
    }

    return const LocationSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter,
    );
  }
}
