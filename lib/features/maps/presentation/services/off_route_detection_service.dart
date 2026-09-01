/// Detects sustained off-route conditions and triggers reroute requests.
///
/// A single GPS reading 60 m from the route is not enough — that could be
/// GPS jitter or a parking lot detour. Five consecutive readings off-route
/// over ~10 seconds is a strong signal the user has actually deviated and
/// needs a new route.
class OffRouteDetectionService {
  /// Distance (metres) beyond which a reading is treated as off-route.
  static const double offRouteThresholdMetres = 50.0;

  /// A route this far from the first live fix is stale, not GPS jitter. This
  /// commonly happens when the app resumes after the driver has moved while
  /// the screen was off, so reroute immediately instead of waiting for a
  /// multi-reading confirmation window.
  static const double grossDeviationThresholdMetres = 125.0;

  /// Consecutive off-route readings required to trigger a reroute.
  static const int sustainedReadingsRequired = 5;

  /// Cooldown after a reroute to prevent rapid re-triggering.
  static const Duration rerouteCooldown = Duration(seconds: 15);

  final Future<void> Function() onRerouteNeeded;

  int _consecutiveOffRouteReadings = 0;
  DateTime? _lastRerouteAt;

  /// Counts reroutes fired during this journey. The first reroute uses a
  /// tighter threshold (3 readings) for a faster initial response. After
  /// that the full [sustainedReadingsRequired] applies to prevent thrashing
  /// on roads that run close to the planned route.
  int _rerouteCount = 0;

  /// Effective threshold for the current reroute attempt.
  int get _effectiveSustainedReadings =>
      _rerouteCount == 0 ? 3 : sustainedReadingsRequired;

  OffRouteDetectionService({required this.onRerouteNeeded});

  /// Process a GPS reading and trigger reroute when sustained off-route
  /// is detected.
  Future<void> processReading({required double deviationMetres}) async {
    if (deviationMetres <= offRouteThresholdMetres) {
      if (_consecutiveOffRouteReadings > 0) {
        _consecutiveOffRouteReadings = 0;
        print('🧭 off-route streak: 0/$sustainedReadingsRequired (reset)');
      }
      return;
    }

    _consecutiveOffRouteReadings++;
    print(
      '🧭 off-route streak: $_consecutiveOffRouteReadings/$_effectiveSustainedReadings',
    );

    final isGrossInitialDeviation =
        _rerouteCount == 0 && deviationMetres >= grossDeviationThresholdMetres;
    if (!isGrossInitialDeviation &&
        _consecutiveOffRouteReadings < _effectiveSustainedReadings) {
      return;
    }

    if (_lastRerouteAt != null &&
        DateTime.now().difference(_lastRerouteAt!) < rerouteCooldown) {
      return;
    }

    _rerouteCount++;
    _lastRerouteAt = DateTime.now();
    _consecutiveOffRouteReadings = 0;
    print(
      isGrossInitialDeviation
          ? '🧭 Stale route detected — triggering immediate reroute #$_rerouteCount'
          : '🧭 Off-route sustained — triggering reroute #$_rerouteCount',
    );
    await onRerouteNeeded();
  }

  /// Reset all state. Called when a new route is loaded or journey ends.
  void reset() {
    _consecutiveOffRouteReadings = 0;
    _lastRerouteAt = null;
  }
}
