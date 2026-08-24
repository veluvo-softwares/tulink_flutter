import '../../domain/entities/journey.dart';

/// Decides whether a journey the UI started is still live.
///
/// Extracted from the home screen so the rule can be exercised directly: it
/// governs when a composed draft is retired, and getting it wrong is what let a
/// completed journey be started a second time from a stale draft.
///
/// [JourneyProvider.endJourney] clears `currentJourney` and drops the journey
/// from `activeJourneys`, so absence from both is the signal that it finished.
bool isJourneyFinished({
  required String journeyId,
  required Journey? currentJourney,
  required List<Journey> activeJourneys,
}) {
  if (currentJourney?.id == journeyId) return false;
  return !activeJourneys.any((journey) => journey.id == journeyId);
}
