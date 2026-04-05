import '../../../../core/common/result.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/invitation.dart';
import '../repositories/invitation_repository.dart';

class GetParticipantsUseCase implements UseCase<List<JourneyParticipant>, String> {
  final InvitationRepository repository;

  GetParticipantsUseCase(this.repository);

  @override
  Future<Result<List<JourneyParticipant>>> call(String journeyId) {
    return repository.getParticipants(journeyId);
  }
}