import 'package:flutter/material.dart';
import 'package:tulink_flutter/core/common/result.dart';
import 'package:tulink_flutter/core/errors/failure.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';
import 'package:tulink_flutter/features/journeys/domain/usecases/journey_usecases.dart';

class JourneyProvider extends ChangeNotifier {
  final CreateJourney createJourneyUseCase;
  final GetJourneyById getJourneyByIdUseCase;
  final GetActiveJourneys getActiveJourneysUseCase;
  final JoinJourneyByCode joinJourneyByCodeUseCase;
  final StartJourney startJourneyUseCase;
  final UpdateJourney updateJourneyUseCase;
  final EndJourney endJourneyUseCase;
  final SwitchActiveJourney switchActiveJourneyUseCase;
  final CancelJourney cancelJourneyUseCase;
  final LeaveJourney leaveJourneyUseCase;

  /// Optional so existing construction sites keep working; without it the
  /// provider simply has nothing to paint before the network answers.
  final GetCachedActiveJourneys? getCachedActiveJourneysUseCase;

  JourneyProvider({
    required this.createJourneyUseCase,
    required this.getJourneyByIdUseCase,
    required this.getActiveJourneysUseCase,
    required this.joinJourneyByCodeUseCase,
    required this.startJourneyUseCase,
    required this.updateJourneyUseCase,
    required this.endJourneyUseCase,
    required this.switchActiveJourneyUseCase,
    required this.cancelJourneyUseCase,
    required this.leaveJourneyUseCase,
    this.getCachedActiveJourneysUseCase,
  });

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  Journey? _currentJourney;
  Journey? get currentJourney => _currentJourney;

  /// Monotonic token for journey fetches. A response may only be installed as
  /// the shared selection while it is still the newest request — a slow fetch
  /// for A landing after the user selected B used to overwrite B.
  int _fetchSeq = 0;
  int _latestFetch = 0;

  /// Incremented on every change of [currentJourney], whatever caused it.
  ///
  /// Callers that await across a selection change read this before and after
  /// and abandon the transition if it moved. It is the one token that covers
  /// *all* the ways selection changes — fetch, explicit set, release, end —
  /// which per-call-site flags never did.
  int _selectionGeneration = 0;
  int get selectionGeneration => _selectionGeneration;

  /// Adopt [journey] as the selection and invalidate every pending fetch.
  ///
  /// An explicit selection outranks anything still in flight: without this a
  /// fetch issued before the switch lands afterwards and silently reinstates
  /// the journey the user just moved away from.
  void _select(Journey? journey) {
    _latestFetch = ++_fetchSeq;
    // Only a change of *identity* is a selection change. Re-installing a fresh
    // entity for the same journey (a roster refresh, a status update) must not
    // invalidate transitions that are legitimately in flight for it.
    final changedIdentity = _currentJourney?.id != journey?.id;
    _currentJourney = journey;
    if (changedIdentity) _selectionGeneration++;
  }

  List<Journey> _activeJourneys = [];
  List<Journey> get activeJourneys => _activeJourneys;

  /// Holds the completed journey returned by [endJourney] for one-shot use
  /// by the map screen. Cleared after consumption via [consumeLastCompletedJourney].
  Journey? _lastCompletedJourney;
  Journey? get lastCompletedJourney => _lastCompletedJourney;

  /// Set when [startJourney] is rejected by the backend with
  /// ALREADY_IN_ACTIVE_JOURNEY (409): the id of the journey the user already has
  /// ACTIVE. Lets the UI offer an end-it-and-start-this switch. Cleared on the
  /// next [startJourney] attempt.
  String? _activeJourneyConflictId;
  String? get activeJourneyConflictId => _activeJourneyConflictId;

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String? value) {
    _error = value;
    notifyListeners();
  }

  Future<bool> createJourney({
    required String name,
    required double latitude,
    required double longitude,
    String? destinationName,
    required String destinationAddress,
    required int lagThresholdMeters,
    DateTime? scheduledFor,
    bool autoStart = false,
  }) async {
    _setLoading(true);
    _setError(null);

    final result = await createJourneyUseCase(
      name: name,
      latitude: latitude,
      longitude: longitude,
      destinationName: destinationName,
      destinationAddress: destinationAddress,
      lagThresholdMeters: lagThresholdMeters,
      scheduledFor: scheduledFor,
      autoStart: autoStart,
    );

    if (result.isSuccess && result.data != null) {
      _select(result.data);
      _setLoading(false);
      return true;
    } else {
      _setError(result.failure?.message ?? 'Unknown error');
      _setLoading(false);
      return false;
    }
  }

  Future<void> fetchActiveJourneys() async {
    _setLoading(true);
    _setError(null);

    // Paint what the device already knows before waiting on the network, so a
    // returning driver is not shown "no active journeys" for the second or two
    // it takes the request to answer.
    await _hydrateActiveJourneysFromCache();

    final result = await getActiveJourneysUseCase();

    if (result.isSuccess && result.data != null) {
      _activeJourneys = result.data!;

      // Reconcile _currentJourney against the server-authoritative list.
      // If we still have an ACTIVE journey in memory but the server no longer
      // lists it as active, it was completed/cancelled — clear the stale state
      // so the home screen banner disappears.
      if (_currentJourney != null &&
          (_currentJourney!.status == JourneyStatus.PENDING ||
              _currentJourney!.status == JourneyStatus.ACTIVE)) {
        final stillActive = _activeJourneys.any(
          (j) => j.id == _currentJourney!.id,
        );
        if (!stillActive) {
          _select(null);
        }
      }

      if (_currentJourney == null && _activeJourneys.isNotEmpty) {
        _select(_activeJourneys.first);
      }
    } else {
      _setError(result.failure?.message ?? 'Unknown error');
    }

    _setLoading(false);
  }

  /// Seed the active list from disk and paint.
  ///
  /// Deliberately does not run the reconciliation that follows a real fetch.
  /// That logic clears [_currentJourney] when the server stops listing it,
  /// which is only meaningful against a server-authoritative answer — applying
  /// it to cached data would let a stale cache retire a live journey.
  Future<void> _hydrateActiveJourneysFromCache() async {
    final useCase = getCachedActiveJourneysUseCase;
    if (useCase == null || _activeJourneys.isNotEmpty) return;

    try {
      final cached = await useCase();
      if (cached.isEmpty) return;

      _activeJourneys = cached;
      if (_currentJourney == null) _select(cached.first);
      notifyListeners();
    } catch (e) {
      // Cache trouble must never block the live fetch.
      print('⚠️ Could not read cached active journeys: $e');
    }
  }

  /// Fetch a journey by id and return it.
  ///
  /// Returns the fetched journey, or null on failure. **Callers must use the
  /// return value**, not [currentJourney], to decide what to do next: on
  /// failure this deliberately leaves the previous selection intact, so reading
  /// `currentJourney` afterwards can silently yield a *different* journey and
  /// stage the wrong one.
  ///
  /// The returned journey is also validated to match [journeyId]; a mismatched
  /// response is treated as a failure rather than adopted.
  Future<Journey?> fetchJourneyById(String journeyId) async {
    // Claim the newest-request slot before the await. Only the newest fetch
    // may install itself as the shared selection; an older one that finishes
    // afterwards still returns its entity to *its own* caller, which is what
    // lets a roster refresh for A report honestly without touching B.
    final token = ++_fetchSeq;
    _latestFetch = token;

    _setLoading(true);
    _setError(null);

    final result = await getJourneyByIdUseCase(journeyId);
    final fetched = result.data;
    final isCurrent = _latestFetch == token;

    if (result.isSuccess && fetched != null && fetched.id == journeyId) {
      if (isCurrent) {
        final changedIdentity = _currentJourney?.id != fetched.id;
        _currentJourney = fetched;
        if (changedIdentity) _selectionGeneration++;
        _setLoading(false);
      }
      return fetched;
    }

    if (!isCurrent) {
      // Superseded: report the failure to this caller without disturbing the
      // newer request's loading/error state.
      return null;
    }

    if (result.isSuccess && fetched != null && fetched.id != journeyId) {
      // A response for a different journey must never become the selection.
      _setError('Received a different journey than requested');
      _setLoading(false);
      return null;
    }

    _setError(result.failure?.message ?? 'Unknown error');
    _setLoading(false);
    return null;
  }

  Future<Journey?> joinJourneyByCode(String inviteCode) async {
    _setLoading(true);
    _setError(null);

    final result = await joinJourneyByCodeUseCase(inviteCode);
    if (result.isSuccess && result.data != null) {
      final journey = result.data!;
      _select(journey);
      _activeJourneys
        ..removeWhere((item) => item.id == journey.id)
        ..insert(0, journey);
      _setLoading(false);
      return journey;
    }

    _setError(result.failure?.message ?? 'Failed to join journey');
    _setLoading(false);
    return null;
  }

  Future<bool> startJourney(String journeyId) async {
    _setLoading(true);
    _setError(null);
    _activeJourneyConflictId = null;

    final result = await startJourneyUseCase(journeyId);

    if (result.isSuccess && result.data != null) {
      _select(result.data);
      _setLoading(false);
      return true;
    } else {
      final failure = result.failure;
      if (failure is AlreadyInActiveJourneyFailure) {
        // Backend single-active enforcement (BE-FIX-3). Stash the conflicting
        // journey id so the UI can offer to end it and start this one.
        _activeJourneyConflictId = failure.activeJourneyId;
      }
      _setError(failure?.message ?? 'Unknown error');
      _setLoading(false);
      return false;
    }
  }

  /// Resolve an ALREADY_IN_ACTIVE_JOURNEY conflict surfaced by [startJourney]:
  /// end the currently-active journey, then start the requested one (via the
  /// [SwitchActiveJourney] use case). Returns true only if the new journey
  /// actually started.
  Future<bool> switchToJourney({
    required String fromJourneyId,
    required String toJourneyId,
  }) async {
    _setLoading(true);
    _setError(null);
    _activeJourneyConflictId = null;

    final result = await switchActiveJourneyUseCase(
      fromJourneyId: fromJourneyId,
      toJourneyId: toJourneyId,
    );

    if (result.isSuccess && result.data != null) {
      _select(result.data);
      _activeJourneys.removeWhere((j) => j.id == fromJourneyId);
      _setLoading(false);
      return true;
    } else {
      _setError(result.failure?.message ?? 'Unknown error');
      _setLoading(false);
      return false;
    }
  }

  Future<bool> updateJourney({
    required String journeyId,
    required Map<String, dynamic> updateData,
  }) async {
    _setLoading(true);
    _setError(null);

    final result = await updateJourneyUseCase(
      journeyId: journeyId,
      updateData: updateData,
    );

    if (result.isSuccess && result.data != null) {
      _select(result.data);
      _setLoading(false);
      return true;
    } else {
      _setError(result.failure?.message ?? 'Unknown error');
      _setLoading(false);
      return false;
    }
  }

  /// Set the current journey (used for continuing active journeys).
  ///
  /// An explicit selection wins over anything still in flight.
  void setCurrentJourney(Journey journey) {
    _select(journey);
    notifyListeners();
  }

  /// Stop foregrounding the current journey without changing it server-side.
  ///
  /// Used when the user collapses journey chrome to look at the map: the
  /// journey and their membership are untouched, it is simply no longer the
  /// selection driving the map experience. A journey that is genuinely ACTIVE
  /// is deliberately *not* cleared — dropping it would hide a running convoy.
  /// Release a journey that is known to be finished.
  ///
  /// Unlike [clearCurrentJourneySelection] this *does* clear an entry whose
  /// cached status still reads ACTIVE, because the caller has observed the
  /// journey end. Without it a completed journey stays current and the map
  /// re-derives a live convoy for a trip that is already over.
  void releaseFinishedJourney(String journeyId) {
    var changed = false;
    if (_currentJourney?.id == journeyId) {
      _select(null);
      changed = true;
    }
    if (_activeJourneys.any((journey) => journey.id == journeyId)) {
      _activeJourneys.removeWhere((journey) => journey.id == journeyId);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void clearCurrentJourneySelection() {
    final journey = _currentJourney;
    if (journey == null || journey.status == JourneyStatus.ACTIVE) return;
    _select(null);
    notifyListeners();
  }

  /// End a journey.
  ///
  /// Clears [_currentJourney] immediately so the home screen banner
  /// disappears. The completed journey is held in [lastCompletedJourney]
  /// for the map screen to pass to the details screen as an argument.
  Future<bool> endJourney(String journeyId) async {
    _setLoading(true);
    _setError(null);

    final result = await endJourneyUseCase(journeyId);

    if (result.isSuccess && result.data != null) {
      _lastCompletedJourney = result.data;

      // Clear immediately — before notifyListeners — so no rebuild sees ACTIVE.
      _select(null);
      _activeJourneys.removeWhere((j) => j.id == journeyId);

      _setLoading(false);
      return true;
    } else {
      _setError(result.failure?.message ?? 'Unknown error');
      _setLoading(false);
      return false;
    }
  }

  Future<bool> cancelJourney(String journeyId) async {
    return _exitJourney(journeyId, () => cancelJourneyUseCase(journeyId));
  }

  Future<bool> leaveJourney(String journeyId) async {
    return _exitJourney(journeyId, () => leaveJourneyUseCase(journeyId));
  }

  Future<bool> _exitJourney(
    String journeyId,
    Future<Result<bool>> Function() action,
  ) async {
    _setLoading(true);
    _setError(null);

    final result = await action();
    if (result.isSuccess) {
      if (_currentJourney?.id == journeyId) {
        _select(null);
      }
      _activeJourneys.removeWhere((journey) => journey.id == journeyId);
      _setLoading(false);
      return true;
    }

    _setError(result.failure?.message ?? 'Unknown error');
    _setLoading(false);
    return false;
  }

  /// Consume [lastCompletedJourney] after the map screen has passed it to the
  /// details screen. Prevents the same journey from being re-used on re-entry.
  void consumeLastCompletedJourney() {
    _lastCompletedJourney = null;
    notifyListeners();
  }

  /// Explicitly clear the current journey (e.g. after app restart when server
  /// confirms no active journeys remain).
  void clearCurrentJourney() {
    _select(null);
    notifyListeners();
  }
}
