import 'package:flutter/material.dart';
import 'package:tulink_flutter/core/common/result.dart';
import 'package:tulink_flutter/core/errors/failure.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';
import 'package:tulink_flutter/features/journeys/domain/usecases/journey_usecases.dart';

class JourneyProvider extends ChangeNotifier {
  final CreateJourney createJourneyUseCase;
  final GetJourneyById getJourneyByIdUseCase;
  final GetActiveJourneys getActiveJourneysUseCase;
  final StartJourney startJourneyUseCase;
  final UpdateJourney updateJourneyUseCase;
  final EndJourney endJourneyUseCase;

  JourneyProvider({
    required this.createJourneyUseCase,
    required this.getJourneyByIdUseCase,
    required this.getActiveJourneysUseCase,
    required this.startJourneyUseCase,
    required this.updateJourneyUseCase,
    required this.endJourneyUseCase,
  });

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  Journey? _currentJourney;
  Journey? get currentJourney => _currentJourney;

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
    required String destinationAddress,
    required int lagThresholdMeters,
  }) async {
    _setLoading(true);
    _setError(null);

    final result = await createJourneyUseCase(
      name: name,
      latitude: latitude,
      longitude: longitude,
      destinationAddress: destinationAddress,
      lagThresholdMeters: lagThresholdMeters,
    );

    if (result.isSuccess && result.data != null) {
      _currentJourney = result.data;
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

    final result = await getActiveJourneysUseCase();

    if (result.isSuccess && result.data != null) {
      _activeJourneys = result.data!;

      // Reconcile _currentJourney against the server-authoritative list.
      // If we still have an ACTIVE journey in memory but the server no longer
      // lists it as active, it was completed/cancelled — clear the stale state
      // so the home screen banner disappears.
      if (_currentJourney != null &&
          _currentJourney!.status == JourneyStatus.ACTIVE) {
        final stillActive =
            _activeJourneys.any((j) => j.id == _currentJourney!.id);
        if (!stillActive) {
          _currentJourney = null;
        }
      }
    } else {
      _setError(result.failure?.message ?? 'Unknown error');
    }

    _setLoading(false);
  }

  Future<void> fetchJourneyById(String journeyId) async {
    _setLoading(true);
    _setError(null);

    final result = await getJourneyByIdUseCase(journeyId);

    if (result.isSuccess && result.data != null) {
      _currentJourney = result.data;
    } else {
      _setError(result.failure?.message ?? 'Unknown error');
    }

    _setLoading(false);
  }

  Future<bool> startJourney(String journeyId) async {
    _setLoading(true);
    _setError(null);
    _activeJourneyConflictId = null;

    final result = await startJourneyUseCase(journeyId);

    if (result.isSuccess && result.data != null) {
      _currentJourney = result.data;
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
  /// end the currently-active journey, then start the requested one. Returns
  /// true only if the new journey actually started.
  Future<bool> switchToJourney({
    required String fromJourneyId,
    required String toJourneyId,
  }) async {
    final ended = await endJourney(fromJourneyId);
    if (!ended) return false;
    return startJourney(toJourneyId);
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
      _currentJourney = result.data;
      _setLoading(false);
      return true;
    } else {
      _setError(result.failure?.message ?? 'Unknown error');
      _setLoading(false);
      return false;
    }
  }

  /// Set the current journey (used for continuing active journeys)
  void setCurrentJourney(Journey journey) {
    _currentJourney = journey;
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
      _currentJourney = null;
      _activeJourneys.removeWhere((j) => j.id == journeyId);

      _setLoading(false);
      return true;
    } else {
      _setError(result.failure?.message ?? 'Unknown error');
      _setLoading(false);
      return false;
    }
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
    _currentJourney = null;
    notifyListeners();
  }
}

