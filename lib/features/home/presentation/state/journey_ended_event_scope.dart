/// Whether a terminal event belongs to the journey currently owning the map.
///
/// A completion emitted while journey A is ending can remain buffered after
/// A's summary is dismissed. When journey B mounts, that stale event must be
/// consumed without completing B or reopening A's summary.
bool isJourneyEndedEventCurrent({
  required String eventJourneyId,
  required String? selectedJourneyId,
  required String? activeLayerJourneyId,
}) {
  final currentJourneyId = selectedJourneyId ?? activeLayerJourneyId;
  return currentJourneyId == eventJourneyId;
}
