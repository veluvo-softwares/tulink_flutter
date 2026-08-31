import 'dart:async';

import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';

/// App-scoped owner of live convoy coordination.
///
/// Screens only render journey state. This coordinator keeps the socket room
/// and location publisher aligned with the authenticated user's active journey
/// even when no journey screen is mounted.
class LiveJourneyCoordinator {
  /// Creates an app lifecycle owner around journey and convoy operations.
  LiveJourneyCoordinator({
    required bool Function() canCoordinate,
    required Journey? Function() currentJourney,
    required String? Function() coordinatingJourneyId,
    required bool Function() isSubscribed,
    required Future<void> Function(String journeyId) startCoordination,
    required Future<void> Function() stopCoordination,
    required Future<void> Function() refreshActiveJourneys,
    required Future<void> Function() recoverAfterResume,
  }) : _canCoordinate = canCoordinate,
       _currentJourney = currentJourney,
       _coordinatingJourneyId = coordinatingJourneyId,
       _isSubscribed = isSubscribed,
       _startCoordination = startCoordination,
       _stopCoordination = stopCoordination,
       _refreshActiveJourneys = refreshActiveJourneys,
       _recoverAfterResume = recoverAfterResume;

  final bool Function() _canCoordinate;
  final Journey? Function() _currentJourney;
  final String? Function() _coordinatingJourneyId;
  final bool Function() _isSubscribed;
  final Future<void> Function(String journeyId) _startCoordination;
  final Future<void> Function() _stopCoordination;
  final Future<void> Function() _refreshActiveJourneys;
  final Future<void> Function() _recoverAfterResume;

  bool _reconcileRequested = false;
  Future<void>? _reconcileFuture;
  Future<void>? _resumeFuture;

  /// Aligns transport ownership with the latest auth and journey state.
  ///
  /// Calls are coalesced and drained serially. If state changes while an async
  /// start or stop is in flight, another pass observes the newest state before
  /// the operation settles.
  Future<void> reconcile() {
    _reconcileRequested = true;
    final existing = _reconcileFuture;
    if (existing != null) return existing;

    final future = _drainReconciliation();
    _reconcileFuture = future;
    return future.whenComplete(() {
      if (identical(_reconcileFuture, future)) _reconcileFuture = null;
    });
  }

  Future<void> _drainReconciliation() async {
    while (_reconcileRequested) {
      _reconcileRequested = false;
      final desiredJourneyId = _desiredJourneyId();
      final ownedJourneyId = _coordinatingJourneyId();

      if (desiredJourneyId == null) {
        if (ownedJourneyId != null || _isSubscribed()) {
          await _stopCoordination();
        }
        continue;
      }

      // A joined room is healthy ownership even when GPS permission or a fix
      // is unavailable. Do not repeatedly reopen the native permission flow.
      if (ownedJourneyId != desiredJourneyId || !_isSubscribed()) {
        await _startCoordination(desiredJourneyId);
      }
    }
  }

  String? _desiredJourneyId() {
    if (!_canCoordinate()) return null;
    final journey = _currentJourney();
    return journey?.status == JourneyStatus.ACTIVE ? journey!.id : null;
  }

  /// Revalidates the active journey, restores room ownership, then recovers
  /// events and positions missed while Dart execution was suspended.
  Future<void> onAppResumed() {
    final existing = _resumeFuture;
    if (existing != null) return existing;

    final future = _resume();
    _resumeFuture = future;
    return future.whenComplete(() {
      if (identical(_resumeFuture, future)) _resumeFuture = null;
    });
  }

  Future<void> _resume() async {
    if (_canCoordinate()) await _refreshActiveJourneys();
    await reconcile();
    if (_desiredJourneyId() != null) await _recoverAfterResume();
    await reconcile();
  }
}
