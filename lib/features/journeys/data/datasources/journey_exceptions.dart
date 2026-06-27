/// Data-layer exceptions for the journeys feature.
///
/// These wrap transport/wire concerns (HTTP status, the backend error
/// envelope) so the repository can translate them into domain [Failure]s
/// without itself parsing the wire format.
library;

/// Raised by [JourneyRemoteDataSource.startJourney] when the backend rejects a
/// start because the user already has an ACTIVE journey (HTTP 409, code
/// `ALREADY_IN_ACTIVE_JOURNEY`). Carries the offending [activeJourneyId] so the
/// repository can surface a domain `AlreadyInActiveJourneyFailure` and the UI
/// can offer an end-it-and-start-this switch.
class AlreadyInActiveJourneyException implements Exception {
  const AlreadyInActiveJourneyException({this.activeJourneyId, this.message});

  final String? activeJourneyId;
  final String? message;

  @override
  String toString() =>
      'AlreadyInActiveJourneyException(activeJourneyId: $activeJourneyId)';
}
