/// How the server answered a WebSocket `location-update`.
///
/// The client used to treat *any* answer as success, so a rejection removed
/// the point from the offline outbox and skipped the REST fallback — silent
/// data loss. Every outcome below is derived from the backend's own ack
/// payload (`apps/api/src/modules/location/location.gateway.ts`).
enum LocationAckOutcome {
  /// The server took the point: it was persisted and either broadcast
  /// (`strategy: REALTIME`), queued for a batch flush (`BATCHED`), or cached
  /// for pollers (`POLLING`). These acks carry no `accepted` field.
  accepted,

  /// `accepted: false, reason: THROTTLED_OR_DUPLICATE`.
  ///
  /// Two server behaviours share this code and both mean "do not resend":
  ///
  /// * **duplicate** — `LocationService.processLocationUpdate` sets a 2 s
  ///   `dedup:loc:<user>:<journey>:<lat5>:<lng5>` key with `NX`; losing that
  ///   race means the twin (HTTP or WebSocket) is already being processed, so
  ///   the server *has* the position;
  /// * **throttled** — `PriorityService.shouldThrottle` returned true, so the
  ///   server *intentionally suppressed* this sample at this cadence.
  ///
  /// Neither is a delivery failure, so the point is acknowledged out of the
  /// outbox. Resending would just lose the same race again.
  suppressed,

  /// `accepted: false` with a retryable reason (`SERVER_ERROR`), or any answer
  /// the client could not correlate. The server does **not** have the point:
  /// the gateway's catch block runs before persistence. Keep it queued and use
  /// the REST fallback.
  retryable,

  /// `accepted: false` with a terminal reason: the caller is not a participant,
  /// the journey is not active, or the payload failed validation. Retrying
  /// cannot succeed, so this surfaces as a typed failure instead of looping.
  terminal,
}

/// A correlated answer to one published point.
class LocationPublishAck {
  const LocationPublishAck({
    required this.outcome,
    this.reason,
    this.sequenceNumber,
    this.strategy,
  });

  const LocationPublishAck.accepted({this.sequenceNumber, this.strategy})
    : outcome = LocationAckOutcome.accepted,
      reason = null;

  final LocationAckOutcome outcome;

  /// The server's `reason` code, or a client-side marker for an ack that could
  /// not be correlated (`MALFORMED_ACK`, `ACK_TIMEOUT`).
  final String? reason;
  final int? sequenceNumber;
  final String? strategy;

  /// True when the server holds the point (or deliberately dropped it), so the
  /// client may retire it from the outbox.
  bool get isDelivered =>
      outcome == LocationAckOutcome.accepted ||
      outcome == LocationAckOutcome.suppressed;

  /// True when the point must stay queued and be retried elsewhere.
  bool get isRetryable => outcome == LocationAckOutcome.retryable;

  /// Reason codes the backend uses for rejections that retrying cannot fix.
  static const Set<String> terminalReasons = {
    'NOT_PARTICIPANT',
    'JOURNEY_NOT_ACTIVE',
    'VALIDATION_ERROR',
    'UNAUTHORIZED',
  };

  /// Reason codes that mean "the server has it, or chose to drop it".
  static const Set<String> suppressedReasons = {'THROTTLED_OR_DUPLICATE'};

  /// Classify a raw `location-update-ack` payload.
  ///
  /// An ack that omits `accepted` is an acceptance — that is the shape every
  /// success path in the gateway emits (`REALTIME`, `BATCHED`, `POLLING`).
  static LocationPublishAck fromPayload(Map<Object?, Object?> data) {
    final accepted = data['accepted'];
    final reason = data['reason']?.toString();
    final sequenceNumber = data['sequenceNumber'] is int
        ? data['sequenceNumber']! as int
        : null;
    final strategy = data['strategy']?.toString();

    if (accepted == null || accepted == true) {
      return LocationPublishAck(
        outcome: LocationAckOutcome.accepted,
        sequenceNumber: sequenceNumber,
        strategy: strategy,
      );
    }

    if (reason != null && suppressedReasons.contains(reason)) {
      return LocationPublishAck(
        outcome: LocationAckOutcome.suppressed,
        reason: reason,
        sequenceNumber: sequenceNumber,
      );
    }

    if (reason != null && terminalReasons.contains(reason)) {
      return LocationPublishAck(
        outcome: LocationAckOutcome.terminal,
        reason: reason,
      );
    }

    // Unknown or explicitly retryable (`SERVER_ERROR`). Never assume delivery
    // from a code we do not recognise.
    return LocationPublishAck(
      outcome: LocationAckOutcome.retryable,
      reason: reason ?? 'UNKNOWN',
    );
  }

  /// No correlated answer arrived inside the publish window.
  static const LocationPublishAck timedOut = LocationPublishAck(
    outcome: LocationAckOutcome.retryable,
    reason: 'ACK_TIMEOUT',
  );

  /// An answer arrived that could not be tied to a specific point.
  static const LocationPublishAck malformed = LocationPublishAck(
    outcome: LocationAckOutcome.retryable,
    reason: 'MALFORMED_ACK',
  );

  @override
  String toString() =>
      'LocationPublishAck(${outcome.name}${reason == null ? '' : ', $reason'})';
}
