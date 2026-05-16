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

  const JourneyEndedEvent({
    required this.journeyId,
    this.reason,
    this.endedBy,
    this.endedAt,
  });

  factory JourneyEndedEvent.fromJson(String journeyId, Map<String, dynamic> json) {
    final endedAtStr = json['endedAt']?.toString();
    return JourneyEndedEvent(
      journeyId: journeyId,
      reason: json['reason']?.toString(),
      endedBy: json['endedBy']?.toString(),
      endedAt: endedAtStr != null ? DateTime.tryParse(endedAtStr) : null,
    );
  }

  @override
  List<Object?> get props => [journeyId, reason, endedBy, endedAt];
}
