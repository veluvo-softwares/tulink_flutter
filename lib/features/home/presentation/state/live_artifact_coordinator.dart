import 'dart:async';

import '../../../maps/presentation/controllers/live_artifact_cleaner.dart';

/// Owns the completion → cleaning → exploring transition for the shared map.
///
/// The shipped Done handler launched cleanup without awaiting it and dismissed
/// the summary immediately, so the map reported "exploring" while journey A's
/// route, destination, peers and puck were still being deleted — and journey B
/// could start drawing into the middle of that. The removals are sequential
/// platform calls, so B's geometry then got caught by A's remaining deletes.
///
/// This coordinator makes the transition atomic from both points of view:
///
/// * the **user** keeps the completion summary, in an explicit cleaning state,
///   until the surface is genuinely clear;
/// * the **map owner** cannot adopt B until A's cleanup has settled.
///
/// Cleanup failure is reported honestly rather than being papered over — a map
/// that could not be cleared is not an exploring map.
class LiveArtifactCoordinator {
  LiveArtifactCoordinator({required LiveArtifactCleaner cleaner})
    : _cleaner = cleaner;

  final LiveArtifactCleaner _cleaner;

  /// The journey whose drawings are currently on the shared surface.
  String? _journeyId;

  bool _isCleaning = false;

  /// True while the surface is being cleared.
  bool get isCleaning => _isCleaning;

  String? get journeyId => _journeyId;

  /// Record that [journeyId]'s drawings now own the surface.
  void adopt(String journeyId) {
    _journeyId = journeyId;
    // Re-entering a journey we previously cleaned means fresh drawings.
    _cleaner.forget(journeyId);
  }

  /// Wait for any cleanup in flight to settle.
  ///
  /// Callers about to draw a *different* journey must await this first, or
  /// their geometry lands in the middle of someone else's removals.
  Future<void> settle() async {
    final inFlight = _cleaner.inFlight;
    if (inFlight == null) return;
    await inFlight.catchError((Object _) {});
  }

  /// Clear the surface of the journey currently drawn on it.
  ///
  /// Returns true only when the surface is known to be clean. False means the
  /// caller must keep treating it as dirty — it must not report exploring.
  Future<bool> clear({VoidCallback? onStateChanged}) async {
    final journeyId = _journeyId;
    if (journeyId == null) return true;
    if (_isCleaning) {
      // A second Done while the first is still running is the same request.
      await settle();
      return _journeyId == null;
    }

    _isCleaning = true;
    onStateChanged?.call();
    bool cleaned;
    try {
      cleaned = await _cleaner.clear(journeyId: journeyId);
    } catch (_) {
      cleaned = false;
    } finally {
      _isCleaning = false;
      onStateChanged?.call();
    }

    if (cleaned && _journeyId == journeyId) _journeyId = null;
    return cleaned;
  }
}

/// Local alias so this file does not depend on Flutter.
typedef VoidCallback = void Function();
