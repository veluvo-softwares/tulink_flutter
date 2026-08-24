import 'dart:async';

import 'live_map_artifacts.dart';

/// Owns *when* the live convoy's map drawings are removed.
///
/// Cleanup is deliberately not tied to widget disposal. It has to happen on an
/// explicit user action (dismissing the completion summary, cancelling, or
/// switching destination) while the map channel is still usable, and it has to
/// be safe against the two ways a late cleanup can destroy the wrong thing:
///
/// * a cleanup scheduled for journey A completing after journey B is showing;
/// * a cleanup started against a map surface that has since been rebuilt.
///
/// Both are rejected by comparing the journey and surface generation captured
/// at request time against the values current at execution time.
class LiveArtifactCleaner {
  LiveArtifactCleaner({
    required LiveMapArtifacts? Function() artifacts,
    required int Function() currentGeneration,
    required String? Function() currentJourneyId,
  }) : _artifacts = artifacts,
       _currentGeneration = currentGeneration,
       _currentJourneyId = currentJourneyId;

  final LiveMapArtifacts? Function() _artifacts;
  final int Function() _currentGeneration;
  final String? Function() _currentJourneyId;

  /// Serialises requests so two overlapping cleanups cannot interleave their
  /// removals against the same style.
  Future<void>? _inFlight;

  /// Journeys already cleaned, so a repeated Done is a no-op rather than a
  /// second pass over a style that no longer has the layers.
  final Set<String> _cleaned = <String>{};

  /// True while a cleanup is running. Exposed for callers that gate UI on it.
  bool get isCleaning => _inFlight != null;

  /// The cleanup currently running, or null. Awaiting it is how a caller makes
  /// the Done transition atomic from the user's point of view.
  Future<void>? get inFlight => _inFlight;

  /// Remove the live drawings belonging to [journeyId].
  ///
  /// [journeyId] is the journey whose artifacts these are — *not* necessarily
  /// the journey now selected. Passing it explicitly is what lets a late
  /// request be rejected instead of erasing a newer journey's route.
  ///
  /// Returns true when the surface is known to be clean for [journeyId]. False
  /// means the cleanup was rejected or abandoned part-way — the caller must
  /// treat the surface as still dirty rather than reporting it as exploring.
  Future<bool> clear({required String journeyId, bool force = false}) async {
    if (!force && _cleaned.contains(journeyId)) return true;

    final generation = _currentGeneration();
    final previous = _inFlight;
    final future = _clearInternal(journeyId, generation, previous);
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  Future<bool> _clearInternal(
    String journeyId,
    int generation,
    Future<void>? previous,
  ) async {
    if (previous != null) {
      // Await rather than race; a half-applied removal leaves orphan layers.
      await previous.catchError((Object _) {});
    }

    /// Ownership, re-evaluated on demand.
    ///
    /// Checking it once before a batch of sequential platform-channel removals
    /// is not enough: journey B can take the surface between any two removals,
    /// and the rest of A's cleanup then deletes B's geometry.
    bool stillOurs() {
      // The surface was rebuilt: its style has none of these artifacts, and
      // whichever layer owns the new surface redraws its own.
      if (_currentGeneration() != generation) return false;
      // Another journey has taken over. Erasing now would wipe *its* geometry.
      final selected = _currentJourneyId();
      return selected == null || selected == journeyId;
    }

    if (!stillOurs()) return false;

    final artifacts = _artifacts();
    if (artifacts == null) return false;

    final completed = await artifacts.clearAll(isStillValid: stillOurs);

    // Abandoned part-way, or the surface was rebuilt while the removals were
    // in flight: the work went to a style that is gone or to geometry that is
    // no longer ours, so it does not count as cleaned — otherwise these layers
    // would never be removed from the surface that still has them.
    if (!completed || !stillOurs()) return false;
    _cleaned.add(journeyId);
    return true;
  }

  /// Allow [journeyId] to be cleaned again — used when a journey is restarted
  /// ("Go again") so its fresh drawings are not mistaken for already-removed
  /// ones.
  void forget(String journeyId) => _cleaned.remove(journeyId);
}
