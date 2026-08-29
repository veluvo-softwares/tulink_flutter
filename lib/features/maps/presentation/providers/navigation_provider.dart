import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' as geo;

import '../../../../core/services/connectivity_service.dart';
import '../../../../core/services/journey_location_service.dart';
import '../../../../core/services/offline_storage_service.dart';
import '../../data/models/route_result_model.dart';
import '../../domain/entities/last_known_progress.dart';
import '../../domain/entities/maneuver.dart';
import '../../domain/entities/route_progress.dart';
import '../services/maneuver_tracker_service.dart';
import '../services/map_matching_service.dart';
import '../services/off_route_detection_service.dart';
import '../services/voice_instruction_service.dart';

/// Orchestrates the turn-by-turn navigation experience for an active journey.
///
/// Subscribes to high-frequency GPS updates, snaps each reading to the
/// route, tracks maneuver progress, fires voice announcements, and detects
/// off-route conditions. Emits a [RouteProgress] snapshot on every update
/// via [notifyListeners].
///
/// Lifecycle:
/// 1. [startNavigation] — called by `TulinkMapScreen` once a route is
///    fetched and the journey is ACTIVE.
/// 2. Progress emits as long as the GPS stream produces values.
/// 3. [stopNavigation] — called when the journey ends or the screen
///    disposes.
class NavigationProvider with ChangeNotifier {
  final ManeuverTrackerService _maneuverTracker;
  final VoiceInstructionService _voiceService;
  final ConnectivityService _connectivityService;
  final OfflineStorageService? _offlineStorage;
  final Future<String?> Function()? _currentUserId;
  final Future<bool?> Function()? _loadVoiceEnabled;
  final Future<void> Function(bool enabled)? _saveVoiceEnabled;
  final JourneyLocationService _journeyLocationService;
  late final OffRouteDetectionService _offRouteDetector;

  StreamSubscription<geo.Position>? _positionSubscription;
  StreamSubscription<bool>? _connectivitySubscription;
  RouteResultModel? _activeRoute;
  RouteProgress? _currentProgress;

  Future<void> Function()? _onRerouteCallback;
  bool _offlineReroutePending = false;
  String? _journeyId;
  int? _restoredSegmentIndex;
  LastKnownProgress? _lastKnownProgress;
  DateTime? _lastProgressPersistedAt;

  NavigationProvider({
    required JourneyLocationService journeyLocationService,
    ManeuverTrackerService? maneuverTracker,
    VoiceInstructionService? voiceService,
    ConnectivityService? connectivityService,
    OfflineStorageService? offlineStorage,
    Future<String?> Function()? currentUserId,
    Future<bool?> Function()? loadVoiceEnabled,
    Future<void> Function(bool enabled)? saveVoiceEnabled,
  }) : _maneuverTracker = maneuverTracker ?? ManeuverTrackerService(),
       _voiceService = voiceService ?? VoiceInstructionService(),
       _connectivityService = connectivityService ?? ConnectivityService(),
       _offlineStorage = offlineStorage,
       _currentUserId = currentUserId,
       _loadVoiceEnabled = loadVoiceEnabled,
       _saveVoiceEnabled = saveVoiceEnabled,
       _journeyLocationService = journeyLocationService {
    _offRouteDetector = OffRouteDetectionService(
      onRerouteNeeded: () async {
        if (_onRerouteCallback != null) {
          if (!_connectivityService.isOnline.value) {
            _offlineReroutePending = true;
            print('📴 Off route while offline — retaining the cached route');
            notifyListeners();
            return;
          }
          // Fire-and-forget the voice announcement — the route fetch must not
          // wait on TTS latency. Errors are swallowed so a voice failure
          // cannot prevent the reroute from starting.
          unawaited(
            _voiceService.speakImmediate('Recalculating route').catchError((
              Object e,
            ) {
              print('⚠️ Voice announcement failed: $e');
            }),
          );
          await _onRerouteCallback!();
        }
      },
    );
    _connectivitySubscription = _connectivityService.transitions.listen((
      online,
    ) {
      if (online && _offlineReroutePending && _onRerouteCallback != null) {
        _offlineReroutePending = false;
        notifyListeners();
        unawaited(_rerouteOnline());
      }
    });
  }

  bool get offlineReroutePending => _offlineReroutePending;

  /// The current route being navigated, or null when navigation is inactive.
  RouteResultModel? get activeRoute => _activeRoute;

  /// Latest progress snapshot. Null until the first GPS reading arrives.
  RouteProgress? get currentProgress => _currentProgress;

  /// Progress recovered from disk, for the window between opening a journey
  /// and the first live fix. Cleared once [currentProgress] takes over, so a
  /// caller preferring live data can simply fall back to this when null.
  LastKnownProgress? get lastKnownProgress =>
      _currentProgress != null ? null : _lastKnownProgress;

  /// Whether navigation is currently active.
  bool get isNavigating => _positionSubscription != null;

  /// Whether voice instructions are enabled.
  bool get isVoiceEnabled => _voiceService.isEnabled;

  /// The restored route cursor, exposed for state-transition tests.
  @visibleForTesting
  int? get restoredSegmentIndexForTesting => _restoredSegmentIndex;

  /// Seeds a restored cursor for state-transition tests.
  @visibleForTesting
  void setRestoredSegmentIndexForTesting(int? segmentIndex) {
    _restoredSegmentIndex = segmentIndex;
  }

  /// Restores the device-level voice guidance preference before app startup.
  Future<void> initializePreferences() async {
    final loadVoiceEnabled = _loadVoiceEnabled;
    if (loadVoiceEnabled == null) return;
    try {
      _voiceService.isEnabled = await loadVoiceEnabled() ?? true;
    } catch (error) {
      debugPrint('Could not restore voice navigation preference: $error');
    }
  }

  /// All maneuvers for the active route. Empty when not navigating.
  List<Maneuver> get maneuvers => _maneuverTracker.maneuvers;

  /// Start navigation for the given route.
  Future<void> startNavigation({
    required RouteResultModel route,
    required Future<void> Function() onRerouteNeeded,
    String? journeyId,
  }) async {
    print('🧭 NavigationProvider: starting navigation');

    _onRerouteCallback = onRerouteNeeded;
    _journeyId = journeyId;
    _activeRoute = route;
    await _restoreProgressCursor();
    _maneuverTracker.loadRoute(route);
    _offRouteDetector.reset();
    _offlineReroutePending = false;
    await _voiceService.init();
    // Pre-warm the platform TTS engine with a silent utterance so the first
    // real announcement (a turn instruction or "Recalculating route") doesn't
    // pay Android's 500ms–2s cold-start cost. A single space is used because
    // flutter_tts treats empty string as a no-op on some platforms while still
    // initialising the engine for a whitespace string.
    unawaited(
      _voiceService.speakImmediate(' ').catchError((Object e) {
        print('⚠️ TTS pre-warm failed: $e');
      }),
    );

    await _positionSubscription?.cancel();
    _positionSubscription = _journeyLocationService.positions.listen(
      _onPositionUpdate,
      onError: (Object e) => print('⚠️ Navigation GPS stream error: $e'),
    );

    final latest = _journeyLocationService.latestPosition;
    if (latest != null) await _onPositionUpdate(latest);

    notifyListeners();
  }

  /// Replace the active route mid-journey (after a reroute).
  void loadRoute(RouteResultModel route) {
    print('🧭 NavigationProvider: loading new route');
    _activeRoute = route;
    // A reroute is a new geometry. Neither the live progress nor the cursor
    // restored from the previous route may constrain matching on this route.
    _currentProgress = null;
    _restoredSegmentIndex = null;
    _lastKnownProgress = null;
    _maneuverTracker.loadRoute(route);
    _offRouteDetector.reset();
    _offlineReroutePending = false;
    notifyListeners();
  }

  /// Stop navigation and release all resources. Safe to call multiple times.
  Future<void> stopNavigation() async {
    print('🧭 NavigationProvider: stopping navigation');

    await _positionSubscription?.cancel();
    _positionSubscription = null;

    await _voiceService.stop();
    _maneuverTracker.clear();
    _offRouteDetector.reset();

    _activeRoute = null;
    _currentProgress = null;
    _onRerouteCallback = null;
    _offlineReroutePending = false;
    _journeyId = null;
    _restoredSegmentIndex = null;
    _lastKnownProgress = null;
    _lastProgressPersistedAt = null;

    notifyListeners();
  }

  /// Toggle voice instructions on or off.
  void setVoiceEnabled(bool enabled) {
    _voiceService.isEnabled = enabled;
    if (!enabled) {
      _voiceService.stop();
    }
    notifyListeners();
    final saveVoiceEnabled = _saveVoiceEnabled;
    if (saveVoiceEnabled != null) {
      unawaited(
        saveVoiceEnabled(enabled).catchError((Object error) {
          debugPrint('Could not save voice navigation preference: $error');
        }),
      );
    }
  }

  Future<void> _onPositionUpdate(geo.Position position) async {
    final route = _activeRoute;
    if (route == null) return;

    final snap = MapMatchingService.snap(
      rawLatitude: position.latitude,
      rawLongitude: position.longitude,
      route: route.coordinates,
      currentSegmentIndex:
          _currentProgress?.currentSegmentIndex ?? _restoredSegmentIndex,
    );
    print(
      '🧭 dev=${snap.deviationMetres.toStringAsFixed(1)}m '
      'segIdx=${snap.segmentIndex} onRoute=${snap.isOnRoute}',
    );

    final maneuverProgress = _maneuverTracker.update(
      snappedLatitude: snap.snappedLatitude,
      snappedLongitude: snap.snappedLongitude,
      segmentIndex: snap.segmentIndex,
    );

    final maneuver = _maneuverTracker.currentManeuver;
    if (maneuver != null) {
      await _voiceService.announce(
        maneuver: maneuver,
        distanceToManeuverMetres: maneuverProgress.distanceToNextManeuverMetres,
        isFinalManeuver:
            _maneuverTracker.currentIndex ==
            _maneuverTracker.maneuvers.length - 1,
      );
    }

    final durationRemaining = route.distanceMetres > 0
        ? route.durationSeconds *
              (maneuverProgress.distanceRemainingMetres / route.distanceMetres)
        : 0.0;

    _currentProgress = RouteProgress(
      currentManeuver:
          maneuver ??
          const Maneuver(
            index: 0,
            instruction: 'Continue to destination',
            maneuverType: 'straight',
            distanceMetres: 0,
            cumulativeDistanceMetres: 0,
            coordinate: [0, 0],
          ),
      distanceToNextManeuverMetres:
          maneuverProgress.distanceToNextManeuverMetres,
      distanceRemainingMetres: maneuverProgress.distanceRemainingMetres,
      durationRemainingSeconds: durationRemaining,
      snappedLatitude: snap.snappedLatitude,
      snappedLongitude: snap.snappedLongitude,
      isOffRoute: !snap.isOnRoute,
      currentSegmentIndex: snap.segmentIndex,
    );

    await _offRouteDetector.processReading(
      deviationMetres: snap.deviationMetres,
    );

    await _persistProgress();

    notifyListeners();
  }

  Future<void> _rerouteOnline() async {
    final callback = _onRerouteCallback;
    if (callback == null) return;
    unawaited(
      _voiceService
          .speakImmediate('Recalculating route')
          .catchError(
            (Object error) => print('⚠️ Voice announcement failed: $error'),
          ),
    );
    await callback();
  }

  Future<void> _restoreProgressCursor() async {
    final storage = _offlineStorage;
    final userProvider = _currentUserId;
    final journeyId = _journeyId;
    if (storage == null || userProvider == null || journeyId == null) return;
    final userId = await userProvider();
    if (userId == null) return;
    final session = storage.loadSession(userId, journeyId);
    final progress = OfflineStorageService.readMap(
      session?['navigationProgress'],
    );
    _restoredSegmentIndex = (progress?['currentSegmentIndex'] as num?)?.toInt();

    // _persistProgress writes distance, duration and the snapped position
    // alongside the cursor. Reading only the cursor meant the driver stared at
    // "-- km / Calculating ETA" until a GPS fix and a fresh route arrived,
    // while a few-seconds-old answer sat unread on disk.
    _lastKnownProgress = LastKnownProgress.fromStorage(progress);
    if (_lastKnownProgress != null) notifyListeners();
  }

  Future<void> _persistProgress() async {
    final progress = _currentProgress;
    final storage = _offlineStorage;
    final userProvider = _currentUserId;
    final journeyId = _journeyId;
    if (progress == null ||
        storage == null ||
        userProvider == null ||
        journeyId == null) {
      return;
    }
    final now = DateTime.now();
    if (_lastProgressPersistedAt != null &&
        now.difference(_lastProgressPersistedAt!) <
            const Duration(seconds: 5)) {
      return;
    }
    final userId = await userProvider();
    if (userId == null) return;
    await storage.mergeSession(userId, journeyId, {
      'navigationProgress': {
        'currentSegmentIndex': progress.currentSegmentIndex,
        'distanceRemainingMetres': progress.distanceRemainingMetres,
        'durationRemainingSeconds': progress.durationRemainingSeconds,
        'snappedLatitude': progress.snappedLatitude,
        'snappedLongitude': progress.snappedLongitude,
        'positionRecordedAt': now.toUtc().toIso8601String(),
      },
    });
    _lastProgressPersistedAt = now;
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _voiceService.dispose();
    super.dispose();
  }
}
