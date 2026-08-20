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

  /// Remove the live drawings belonging to [journeyId].
  ///
  /// [journeyId] is the journey whose artifacts these are — *not* necessarily
  /// the journey now selected. Passing it explicitly is what lets a late
  /// request be rejected instead of erasing a newer journey's route.
  Future<void> clear({required String journeyId, bool force = false}) async {
    if (!force && _cleaned.contains(journeyId)) return;

    final generation = _currentGeneration();
    final previous = _inFlight;
    final future = _clearInternal(journeyId, generation, previous);
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  Future<void> _clearInternal(
    String journeyId,
    int generation,
    Future<void>? previous,
  ) async {
    if (previous != null) {
      // Await rather than race; a half-applied removal leaves orphan layers.
      await previous.catchError((Object _) {});
    }

    // The surface was rebuilt while we waited: its style has none of these
    // artifacts, and the layer that owns the new surface will redraw its own.
    if (_currentGeneration() != generation) return;

    // Another journey has taken over. Erasing now would wipe *its* geometry.
    final selected = _currentJourneyId();
    if (selected != null && selected != journeyId) return;

    final artifacts = _artifacts();
    if (artifacts == null) return;

    await artifacts.clearAll();

    // The surface may have been rebuilt while the removals were in flight. The
    // work went to a style that is gone, so it does not count as cleaned —
    // otherwise the new surface's copy of these layers would never be removed.
    if (_currentGeneration() != generation) return;
    _cleaned.add(journeyId);
  }

  /// Allow [journeyId] to be cleaned again — used when a journey is restarted
  /// ("Go again") so its fresh drawings are not mistaken for already-removed
  /// ones.
  void forget(String journeyId) => _cleaned.remove(journeyId);
}
