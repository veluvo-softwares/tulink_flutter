import 'package:dio/dio.dart';
import 'package:tulink_flutter/features/invites/data/models/journey_invitation_model.dart';
import 'package:tulink_flutter/features/invites/data/models/user_search_result_model.dart';

abstract class InviteRemoteDataSource {
  Future<List<UserSearchResultModel>> searchUsers(String query);

  Future<String> sendInvite({
    required String journeyId,
    required String invitedUserId,
  });

  Future<List<JourneyInvitationModel>> getInvitations();

  Future<String> acceptInvitation(String journeyId);

  Future<String> declineInvitation(String journeyId);
}

class InviteRemoteDataSourceImpl implements InviteRemoteDataSource {
  final Dio dio;

  InviteRemoteDataSourceImpl({required this.dio});

  @override
  Future<List<UserSearchResultModel>> searchUsers(String query) async {
    final response = await dio.get<Map<String, dynamic>>(
      '/auth/searchUser',
      queryParameters: {'query': query},
    );

    if (response.statusCode == 200 && response.data != null) {
      final data = response.data!['data'] as Map<String, dynamic>?;
      final users = data?['users'] as List<dynamic>?;
      if (users != null) {
        return users
            .map(
              (u) => UserSearchResultModel.fromJson(u as Map<String, dynamic>),
            )
            .toList();
      }
    }
    throw DioException(
      requestOptions: response.requestOptions,
      response: response,
      message: 'Failed to search users',
    );
  }

  @override
  Future<String> sendInvite({
    required String journeyId,
    required String invitedUserId,
  }) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/journeys/$journeyId/invite',
      data: {'invitedUserId': invitedUserId},
    );

    if (response.statusCode == 201 && response.data != null) {
      final data = response.data!['data'] as Map<String, dynamic>?;
      return data?['message']?.toString() ?? 'Invitation sent successfully';
    }
    throw DioException(
      requestOptions: response.requestOptions,
      response: response,
      message: 'Failed to send invitation',
    );
  }

  @override
  Future<List<JourneyInvitationModel>> getInvitations() async {
    final response = await dio.get<Map<String, dynamic>>(
      '/journeys/invitations',
    );

    if (response.statusCode == 200 && response.data != null) {
      final data = response.data!['data'] as List<dynamic>?;
      if (data != null) {
        return data
            .map(
              (inv) =>
                  JourneyInvitationModel.fromJson(inv as Map<String, dynamic>),
            )
            .toList();
      }
    }
    throw DioException(
      requestOptions: response.requestOptions,
      response: response,
      message: 'Failed to get invitations',
    );
  }

  @override
  Future<String> acceptInvitation(String journeyId) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/journeys/$journeyId/accept',
    );

    if (response.statusCode == 200 && response.data != null) {
      final data = response.data!['data'] as Map<String, dynamic>?;
      return data?['message']?.toString() ?? 'Invitation accepted';
    }
    throw DioException(
      requestOptions: response.requestOptions,
      response: response,
      message: 'Failed to accept invitation',
    );
  }

  @override
  Future<String> declineInvitation(String journeyId) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/journeys/$journeyId/decline',
    );

    if (response.statusCode == 200) {
      final data = response.data?['data'] as Map<String, dynamic>?;
      return data?['message']?.toString() ?? 'Invitation declined';
    }
    throw DioException(
      requestOptions: response.requestOptions,
      response: response,
      message: 'Failed to decline invitation',
    );
  }
}
