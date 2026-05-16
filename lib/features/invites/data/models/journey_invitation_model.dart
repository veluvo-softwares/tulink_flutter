import 'package:tulink_flutter/features/invites/domain/entities/journey_invitation.dart';

class InvitedByUserModel extends InvitedByUser {
  const InvitedByUserModel({
    required super.uid,
    required super.displayName,
    required super.email,
  });

  factory InvitedByUserModel.fromJson(Map<String, dynamic> json) {
    return InvitedByUserModel(
      uid: json['uid']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
    );
  }
}

class JourneyInvitationModel extends JourneyInvitation {
  const JourneyInvitationModel({
    required super.journeyId,
    required super.journeyName,
    required super.destination,
    required super.invitedBy,
    required super.invitedAt,
  });

  factory JourneyInvitationModel.fromJson(Map<String, dynamic> json) {
    return JourneyInvitationModel(
      journeyId: json['journeyId']?.toString() ?? '',
      journeyName: json['journeyName']?.toString() ?? '',
      destination: json['destination']?.toString() ?? '',
      invitedBy: InvitedByUserModel.fromJson(
        (json['invitedBy'] as Map<String, dynamic>?) ?? {},
      ),
      invitedAt: DateTime.tryParse(json['invitedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
