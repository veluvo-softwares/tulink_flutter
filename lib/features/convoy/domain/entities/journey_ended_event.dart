import 'package:equatable/equatable.dart';

/// Server-driven signal that a journey has terminated.
/// Emitted by the backend's `journey-ended` socket event when a journey
/// transitions to COMPLETED or CANCELLED. Clients receiving this event
/// MUST stop coordinating that journey and disconnect from its room.
class JourneyEndedEvent extends Equatable {
  final String journeyId;
  final String? reason;
  final String? endedBy;
  final DateTime? endedAt;

  /// The journey as the server saw it when it ended.
  ///
  /// Carried on the event because it is the **only** way a client can obtain
  /// the finished journey: completing it marks every participant `LEFT`, so a
  /// follow-up `GET /journeys/{id}` is rejected with 403 "Not a participant of
  /// this journey". Discarding this payload and re-fetching is what left the
  /// completion summary permanently unavailable after a server-driven end.
  final Map<String, dynamic>? journey;

  const JourneyEndedEvent({
    required this.journeyId,
    this.reason,
    this.endedBy,
    this.endedAt,
    this.journey,
  });

  factory JourneyEndedEvent.fromJson(
    String journeyId,
    Map<String, dynamic> json,
  ) {
    final endedAtStr = json['endedAt']?.toString();
    final rawJourney = json['journey'];
    return JourneyEndedEvent(
      journeyId: journeyId,
      reason: json['reason']?.toString(),
      endedBy: json['endedBy']?.toString(),
      endedAt: endedAtStr != null ? DateTime.tryParse(endedAtStr) : null,
      journey: rawJourney is Map
          ? Map<String, dynamic>.from(rawJourney)
          : null,
    );
  }

  /// Journey id taken from the event payload rather than from local state.
  ///
  /// The gateway sends `{journey: {...}, reason, endedAt, timestamp}`; using
  /// the room the client *thinks* it is in meant an event from a room it had
  /// just left was attributed to the room it had just joined.
  static String? journeyIdFrom(Object? data) {
    String? read(Object? value) {
      if (value is! String) return null;
      final trimmed = value.trim();
      return trimmed.isEmpty || trimmed == 'null' ? null : trimmed;
    }

    if (data is! Map) return null;
    final journey = data['journey'];
    if (journey is Map) {
      return read(journey['id']) ?? read(journey['journeyId']);
    }
    return read(data['journeyId']) ?? read(data['id']);
  }

  @override
  List<Object?> get props => [journeyId, reason, endedBy, endedAt];
}
