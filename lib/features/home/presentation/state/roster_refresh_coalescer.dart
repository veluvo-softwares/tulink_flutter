import 'dart:async';

/// Refresh one journey's roster, returning the id of the journey the server
/// actually answered with, or null on failure.
typedef RefreshRoster = Future<String?> Function(String journeyId);

/// Collapses a burst of `participant-accepted` events into refreshes, on the
/// **trailing** edge.
///
/// A burst is normal: several invitees can accept within the same second, and
/// the leader must end up seeing all of them. The previous behaviour advanced
/// the observed tick and then dropped the request whenever a refresh was
/// already running, so the last acceptance in a burst was routinely lost and
/// only a later, unrelated event could repair the roster.
///
/// The rule here is: **at least one refresh always runs after the newest
/// observed tick.** A refresh in flight does not swallow the ticks that arrive
/// during it — it loops again for them.
class RosterRefreshCoalescer {
  RosterRefreshCoalescer({required RefreshRoster refresh}) : _refresh = refresh;

  final RefreshRoster _refresh;

  int _observed = 0;
  int _served = 0;
  bool _running = false;

  /// The newest tick recorded, whether or not it has been served yet.
  int get observedTick => _observed;

  /// The newest tick a *successful* refresh has covered.
  int get servedTick => _served;

  /// True while a refresh is in flight.
  bool get isRefreshing => _running;

  /// Record a new acceptance tick for [journeyId] and ensure a refresh runs
  /// after it.
  ///
  /// [isStillStaged] is consulted after every await: a roster must never be
  /// installed for a journey the user has moved away from, and leaving the
  /// staging state mid-refresh must abandon the remaining work.
  Future<void> record({
    required int tick,
    required String journeyId,
    required bool Function() isStillStaged,
  }) async {
    if (tick <= _observed) return;
    _observed = tick;
    if (_running) {
      // The loop below will pick this tick up. Dropping the request here is
      // the defect this class exists to remove.
      return;
    }
    _running = true;
    try {
      while (_served != _observed) {
        if (!isStillStaged()) return;
        final serving = _observed;
        final answeredFor = await _refresh(journeyId);

        // Left staging while the request was in flight.
        if (!isStillStaged()) return;

        // Validate the returned identity before anything is treated as this
        // journey's roster.
        if (answeredFor != journeyId) {
          // A failed or mismatched refresh must not mark the tick as served,
          // or only a *further* acceptance could ever repair the roster.
          return;
        }
        _served = serving;
      }
    } finally {
      _running = false;
    }
  }

  /// Forget all progress — used when a different journey is staged.
  void reset() {
    _observed = 0;
    _served = 0;
  }
}
