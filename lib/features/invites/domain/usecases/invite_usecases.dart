import 'package:tulink_flutter/core/common/result.dart';
import 'package:tulink_flutter/features/invites/domain/entities/journey_invitation.dart';
import 'package:tulink_flutter/features/invites/domain/entities/user_search_result.dart';
import 'package:tulink_flutter/features/invites/domain/repositories/invite_repository.dart';

class SearchUsers {
  final InviteRepository repository;

  SearchUsers(this.repository);

  Future<Result<List<UserSearchResult>>> call(String query) {
    return repository.searchUsers(query);
  }
}

class SendInvite {
  final InviteRepository repository;

  SendInvite(this.repository);

  Future<Result<String>> call({
    required String journeyId,
    required String invitedUserId,
  }) {
    return repository.sendInvite(
      journeyId: journeyId,
      invitedUserId: invitedUserId,
    );
  }
}

class GetInvitations {
  final InviteRepository repository;

  GetInvitations(this.repository);

  Future<Result<List<JourneyInvitation>>> call() {
    return repository.getInvitations();
  }
}

class AcceptInvitation {
  final InviteRepository repository;

  AcceptInvitation(this.repository);

  Future<Result<String>> call(String journeyId) {
    return repository.acceptInvitation(journeyId);
  }
}
