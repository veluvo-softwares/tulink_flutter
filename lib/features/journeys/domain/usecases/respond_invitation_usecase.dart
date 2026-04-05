import '../../../../core/common/result.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/invitation.dart';
import '../repositories/invitation_repository.dart';

class RespondInvitationParams {
  final String invitationId;
  final bool accept;

  RespondInvitationParams({
    required this.invitationId,
    required this.accept,
  });
}

class RespondInvitationUseCase implements UseCase<Invitation, RespondInvitationParams> {
  final InvitationRepository repository;

  RespondInvitationUseCase(this.repository);

  @override
  Future<Result<Invitation>> call(RespondInvitationParams params) {
    return repository.respondToInvitation(
      invitationId: params.invitationId,
      accept: params.accept,
    );
  }
}