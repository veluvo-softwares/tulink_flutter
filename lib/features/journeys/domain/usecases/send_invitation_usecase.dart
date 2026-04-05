import '../../../../core/common/result.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/invitation.dart';
import '../repositories/invitation_repository.dart';

class SendInvitationParams {
  final String journeyId;
  final String inviteeId;
  final String? message;

  SendInvitationParams({
    required this.journeyId,
    required this.inviteeId,
    this.message,
  });
}

class SendInvitationUseCase implements UseCase<Invitation, SendInvitationParams> {
  final InvitationRepository repository;

  SendInvitationUseCase(this.repository);

  @override
  Future<Result<Invitation>> call(SendInvitationParams params) {
    return repository.sendInvitation(
      journeyId: params.journeyId,
      inviteeId: params.inviteeId,
      message: params.message,
    );
  }
}