import 'package:equatable/equatable.dart';

class InvitedByUser extends Equatable {
  final String uid;
  final String displayName;
  final String email;

  const InvitedByUser({
    required this.uid,
    required this.displayName,
    required this.email,
  });

  @override
  List<Object?> get props => [uid, displayName, email];
}

class JourneyInvitation extends Equatable {
  final String journeyId;
  final String journeyName;
  final String destination;
  final InvitedByUser invitedBy;
  final DateTime invitedAt;

  const JourneyInvitation({
    required this.journeyId,
    required this.journeyName,
    required this.destination,
    required this.invitedBy,
    required this.invitedAt,
  });

  @override
  List<Object?> get props => [journeyId, journeyName, destination, invitedBy, invitedAt];
}
