import 'package:dio/dio.dart';
import 'package:tulink_flutter/core/common/result.dart';
import 'package:tulink_flutter/core/errors/failure.dart';
import 'package:tulink_flutter/features/invites/data/datasources/invite_remote_data_source.dart';
import 'package:tulink_flutter/features/invites/domain/entities/journey_invitation.dart';
import 'package:tulink_flutter/features/invites/domain/entities/user_search_result.dart';
import 'package:tulink_flutter/features/invites/domain/repositories/invite_repository.dart';

class InviteRepositoryImpl implements InviteRepository {
  final InviteRemoteDataSource remoteDataSource;

  InviteRepositoryImpl({required this.remoteDataSource});

  @override
  Future<Result<List<UserSearchResult>>> searchUsers(String query) async {
    try {
      final results = await remoteDataSource.searchUsers(query);
      return (data: results, failure: null);
    } on DioException catch (e) {
      return (
        data: null,
        failure: ServerFailure(
          message:
              e.response?.data?['message']?.toString() ??
              'Failed to search users',
        ),
      );
    } catch (e) {
      return (data: null, failure: ServerFailure(message: e.toString()));
    }
  }

  @override
  Future<Result<String>> sendInvite({
    required String journeyId,
    required String invitedUserId,
  }) async {
    try {
      final message = await remoteDataSource.sendInvite(
        journeyId: journeyId,
        invitedUserId: invitedUserId,
      );
      return (data: message, failure: null);
    } on DioException catch (e) {
      return (
        data: null,
        failure: ServerFailure(
          message:
              e.response?.data?['message']?.toString() ??
              'Failed to send invitation',
        ),
      );
    } catch (e) {
      return (data: null, failure: ServerFailure(message: e.toString()));
    }
  }

  @override
  Future<Result<List<JourneyInvitation>>> getInvitations() async {
    try {
      final invitations = await remoteDataSource.getInvitations();
      return (data: invitations, failure: null);
    } on DioException catch (e) {
      return (
        data: null,
        failure: ServerFailure(
          message:
              e.response?.data?['message']?.toString() ??
              'Failed to get invitations',
        ),
      );
    } catch (e) {
      return (data: null, failure: ServerFailure(message: e.toString()));
    }
  }

  @override
  Future<Result<String>> acceptInvitation(String journeyId) async {
    try {
      final message = await remoteDataSource.acceptInvitation(journeyId);
      return (data: message, failure: null);
    } on DioException catch (e) {
      return (
        data: null,
        failure: ServerFailure(
          message:
              e.response?.data?['message']?.toString() ??
              'Failed to accept invitation',
        ),
      );
    } catch (e) {
      return (data: null, failure: ServerFailure(message: e.toString()));
    }
  }

  @override
  Future<Result<String>> declineInvitation(String journeyId) async {
    try {
      final message = await remoteDataSource.declineInvitation(journeyId);
      return (data: message, failure: null);
    } on DioException catch (e) {
      return (
        data: null,
        failure: ServerFailure(
          message:
              e.response?.data?['message']?.toString() ??
              'Failed to decline invitation',
        ),
      );
    } catch (e) {
      return (data: null, failure: ServerFailure(message: e.toString()));
    }
  }
}
