/// Low-latency signal that a newer server-owned convoy route was committed.
class RouteUpdatedEvent {
  const RouteUpdatedEvent({
    required this.journeyId,
    required this.routeVersion,
    required this.reason,
    required this.updatedAt,
  });

  final String journeyId;
  final int routeVersion;
  final String reason;
  final DateTime? updatedAt;

  static RouteUpdatedEvent? fromPayload(Object? payload) {
    if (payload is! Map) return null;
    final journeyId = payload['journeyId']?.toString().trim();
    final version = payload['routeVersion'];
    if (journeyId == null || journeyId.isEmpty || version is! num) return null;
    return RouteUpdatedEvent(
      journeyId: journeyId,
      routeVersion: version.toInt(),
      reason: payload['reason']?.toString() ?? 'UNKNOWN',
      updatedAt: DateTime.tryParse(payload['updatedAt']?.toString() ?? ''),
    );
  }
}
