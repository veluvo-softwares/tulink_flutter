import '../../../../core/common/result.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/invitation.dart';
import '../repositories/invitation_repository.dart';

class SearchUsersUseCase implements UseCase<List<User>, String> {
  final InvitationRepository repository;

  SearchUsersUseCase(this.repository);

  @override
  Future<Result<List<User>>> call(String query) {
    return repository.searchUsers(query);
  }
}