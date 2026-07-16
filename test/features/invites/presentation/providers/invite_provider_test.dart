import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/core/common/result.dart';
import 'package:tulink_flutter/features/invites/domain/entities/journey_invitation.dart';
import 'package:tulink_flutter/features/invites/domain/entities/user_search_result.dart';
import 'package:tulink_flutter/features/invites/domain/repositories/invite_repository.dart';
import 'package:tulink_flutter/features/invites/domain/usecases/invite_usecases.dart';
import 'package:tulink_flutter/features/invites/presentation/providers/invite_provider.dart';

void main() {
  test('concurrent forced silent refreshes share one request', () async {
    final repository = _ControlledInviteRepository();
    final provider = InviteProvider(
      searchUsersUseCase: SearchUsers(repository),
      sendInviteUseCase: SendInvite(repository),
      getInvitationsUseCase: GetInvitations(repository),
      acceptInvitationUseCase: AcceptInvitation(repository),
      declineInvitationUseCase: DeclineInvitation(repository),
    );

    final first = provider.refreshInvitationsSilently(force: true);
    final second = provider.refreshInvitationsSilently(force: true);

    expect(repository.getInvitationsCallCount, 1);

    repository.completeInvitations(const <JourneyInvitation>[]);
    await Future.wait(<Future<void>>[first, second]);

    expect(provider.invitations, isEmpty);
    expect(repository.getInvitationsCallCount, 1);
  });
}

class _ControlledInviteRepository implements InviteRepository {
  final Completer<Result<List<JourneyInvitation>>> _invitations = Completer();
  int getInvitationsCallCount = 0;

  void completeInvitations(List<JourneyInvitation> invitations) {
    _invitations.complete(ResultHelper.success(invitations));
  }

  @override
  Future<Result<List<JourneyInvitation>>> getInvitations() {
    getInvitationsCallCount++;
    return _invitations.future;
  }

  @override
  Future<Result<String>> acceptInvitation(String journeyId) =>
      throw UnimplementedError();

  @override
  Future<Result<String>> declineInvitation(String journeyId) =>
      throw UnimplementedError();

  @override
  Future<Result<List<UserSearchResult>>> searchUsers(String query) =>
      throw UnimplementedError();

  @override
  Future<Result<String>> sendInvite({
    required String journeyId,
    required String invitedUserId,
  }) => throw UnimplementedError();
}
