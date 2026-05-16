import 'package:tulink_flutter/core/common/result.dart';
import 'package:tulink_flutter/features/invites/domain/entities/journey_invitation.dart';
import 'package:tulink_flutter/features/invites/domain/entities/user_search_result.dart';

abstract class InviteRepository {
  Future<Result<List<UserSearchResult>>> searchUsers(String query);

  Future<Result<String>> sendInvite({
    required String journeyId,
    required String invitedUserId,
  });

  Future<Result<List<JourneyInvitation>>> getInvitations();

  Future<Result<String>> acceptInvitation(String journeyId);
}
