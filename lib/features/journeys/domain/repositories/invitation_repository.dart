import 'dart:async';
import '../../../../core/common/result.dart';
import '../entities/invitation.dart';

abstract class InvitationRepository {
  Stream<List<Invitation>> get invitationsStream;
  Stream<List<JourneyParticipant>> get participantsStream;

  Future<Result<List<User>>> searchUsers(String query);
  
  Future<Result<Invitation>> sendInvitation({
    required String journeyId,
    required String inviteeId,
    String? message,
  });
  
  Future<Result<Invitation>> respondToInvitation({
    required String invitationId,
    required bool accept,
  });
  
  Future<Result<List<Invitation>>> getInvitations(String journeyId);
  
  Future<Result<List<JourneyParticipant>>> getParticipants(String journeyId);
  
  Future<Result<void>> removeParticipant({
    required String journeyId,
    required String participantId,
  });
  
  Future<Result<void>> cancelInvitation(String invitationId);
  
  void startRealTimeUpdates(String journeyId);
  void stopRealTimeUpdates();
}