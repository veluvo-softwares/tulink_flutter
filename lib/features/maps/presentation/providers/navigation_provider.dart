import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' as geo;

import '../../data/models/route_result_model.dart';
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
  late final OffRouteDetectionService _offRouteDetector;

  StreamSubscription<geo.Position>? _positionSubscription;
  RouteResultModel? _activeRoute;
  RouteProgress? _currentProgress;

  Future<void> Function()? _onRerouteCallback;

  NavigationProvider({
    ManeuverTrackerService? maneuverTracker,
    VoiceInstructionService? voiceService,
  })  : _maneuverTracker = maneuverTracker ?? ManeuverTrackerService(),
        _voiceService = voiceService ?? VoiceInstructionService() {
    _offRouteDetector = OffRouteDetectionService(
      onRerouteNeeded: () async {
        if (_onRerouteCallback != null) {
          // Fire-and-forget the voice announcement — the route fetch must not
          // wait on TTS latency. Errors are swallowed so a voice failure
          // cannot prevent the reroute from starting.
          unawaited(_voiceService.speakImmediate('Recalculating route')
              .catchError((Object e) {
            print('⚠️ Voice announcement failed: $e');
          }));
          await _onRerouteCallback!();
        }
      },
    );
  }

  /// The current route being navigated, or null when navigation is inactive.
  RouteResultModel? get activeRoute => _activeRoute;

  /// Latest progress snapshot. Null until the first GPS reading arrives.
  RouteProgress? get currentProgress => _currentProgress;

  /// Whether navigation is currently active.
  bool get isNavigating => _positionSubscription != null;

  /// Whether voice instructions are enabled.
  bool get isVoiceEnabled => _voiceService.isEnabled;

  /// All maneuvers for the active route. Empty when not navigating.
  List<Maneuver> get maneuvers => _maneuverTracker.maneuvers;

  /// Start navigation for the given route.
  Future<void> startNavigation({
    required RouteResultModel route,
    required Future<void> Function() onRerouteNeeded,
  }) async {
    print('🧭 NavigationProvider: starting navigation');

    _onRerouteCallback = onRerouteNeeded;
    _activeRoute = route;
    _maneuverTracker.loadRoute(route);
    _offRouteDetector.reset();
    await _voiceService.init();
    // Pre-warm the platform TTS engine with a silent utterance so the first
    // real announcement (a turn instruction or "Recalculating route") doesn't
    // pay Android's 500ms–2s cold-start cost. A single space is used because
    // flutter_tts treats empty string as a no-op on some platforms while still
    // initialising the engine for a whitespace string.
    unawaited(_voiceService.speakImmediate(' ').catchError((Object e) {
      print('⚠️ TTS pre-warm failed: $e');
    }));

    await _positionSubscription?.cancel();
    _positionSubscription = geo.Geolocator.getPositionStream(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(
      _onPositionUpdate,
      onError: (Object e) => print('⚠️ Navigation GPS stream error: $e'),
    );

    notifyListeners();
  }

  /// Replace the active route mid-journey (after a reroute).
  void loadRoute(RouteResultModel route) {
    print('🧭 NavigationProvider: loading new route');
    _activeRoute = route;
    _currentProgress = null; // stale segment index from old route must not seed the new snap window
    _maneuverTracker.loadRoute(route);
    _offRouteDetector.reset();
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

    notifyListeners();
  }

  /// Toggle voice instructions on or off.
  void setVoiceEnabled(bool enabled) {
    _voiceService.isEnabled = enabled;
    if (!enabled) {
      _voiceService.stop();
    }
    notifyListeners();
  }

  Future<void> _onPositionUpdate(geo.Position position) async {
    final route = _activeRoute;
    if (route == null) return;

    final snap = MapMatchingService.snap(
      rawLatitude: position.latitude,
      rawLongitude: position.longitude,
      route: route.coordinates,
      currentSegmentIndex: _currentProgress?.currentSegmentIndex,
    );
    print('🧭 dev=${snap.deviationMetres.toStringAsFixed(1)}m '
        'segIdx=${snap.segmentIndex} onRoute=${snap.isOnRoute}');

    final maneuverProgress = _maneuverTracker.update(
      snappedLatitude: snap.snappedLatitude,
      snappedLongitude: snap.snappedLongitude,
      segmentIndex: snap.segmentIndex,
    );

    final maneuver = _maneuverTracker.currentManeuver;
    if (maneuver != null) {
      await _voiceService.announce(
        maneuver: maneuver,
        distanceToManeuverMetres:
            maneuverProgress.distanceToNextManeuverMetres,
        isFinalManeuver: _maneuverTracker.currentIndex ==
            _maneuverTracker.maneuvers.length - 1,
      );
    }

    final durationRemaining = route.distanceMetres > 0
        ? route.durationSeconds *
            (maneuverProgress.distanceRemainingMetres / route.distanceMetres)
        : 0.0;

    _currentProgress = RouteProgress(
      currentManeuver: maneuver ??
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

    notifyListeners();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _voiceService.dispose();
    super.dispose();
  }
}
