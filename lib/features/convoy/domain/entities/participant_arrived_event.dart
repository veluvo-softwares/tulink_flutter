import 'package:equatable/equatable.dart';

/// Server-driven signal that a single participant has reached the destination.
/// Emitted by the backend to every member of the journey room. When
/// [allArrived] is true the backend auto-completes the journey and emits
/// `journey-ended` immediately after — clients must stop publishing GPS on
/// allArrived but defer navigation to the journey-ended handler.
class ParticipantArrivedEvent extends Equatable {
  final String userId;
  final int arrivedCount;
  final int totalCount;
  final bool allArrived;
  final DateTime timestamp;

  const ParticipantArrivedEvent({
    required this.userId,
    required this.arrivedCount,
    required this.totalCount,
    required this.allArrived,
    required this.timestamp,
  });

  factory ParticipantArrivedEvent.fromJson(Map<String, dynamic> json) {
    final raw = json['timestamp'];
    final ts = raw is int
        ? DateTime.fromMillisecondsSinceEpoch(raw)
        : DateTime.tryParse(raw?.toString() ?? '') ?? DateTime.now();

    return ParticipantArrivedEvent(
      userId: json['userId']?.toString() ?? '',
      arrivedCount: (json['arrivedCount'] as num?)?.toInt() ?? 0,
      totalCount: (json['totalCount'] as num?)?.toInt() ?? 0,
      allArrived: json['allArrived'] == true,
      timestamp: ts,
    );
  }

  @override
  List<Object?> get props => [userId, arrivedCount, totalCount, allArrived, timestamp];
}
