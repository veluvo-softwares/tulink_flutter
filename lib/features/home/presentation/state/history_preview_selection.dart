/// Resolves the journey history item that should own the map preview.
///
/// An explicit selection remains authoritative while it is still present.
/// The first journey is only a default for an empty or now-invalid selection.
String? resolveHistoryPreviewId({
  required List<String> availableJourneyIds,
  required String? selectedJourneyId,
}) {
  if (availableJourneyIds.isEmpty) return null;
  if (selectedJourneyId != null &&
      availableJourneyIds.contains(selectedJourneyId)) {
    return selectedJourneyId;
  }
  return availableJourneyIds.first;
}

/// Returns the journey that should show retry UI after a preview attempt.
///
/// A failed request that was superseded by another selection is stale and must
/// not put the newer row into an error state.
String? resolveHistoryPreviewErrorId({
  required String attemptedJourneyId,
  required String? selectedJourneyId,
  required bool routeRendered,
}) {
  if (routeRendered || attemptedJourneyId != selectedJourneyId) return null;
  return attemptedJourneyId;
}
