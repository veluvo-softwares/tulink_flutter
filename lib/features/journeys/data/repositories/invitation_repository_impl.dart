import 'dart:async';

import 'package:tulink_flutter/core/common/result.dart';
import 'package:tulink_flutter/core/errors/failure.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/invitation.dart';
import 'package:tulink_flutter/features/journeys/domain/repositories/invitation_repository.dart';
import 'package:tulink_flutter/features/journeys/data/services/invitation_api_service.dart';

class InvitationRepositoryImpl implements InvitationRepository {
  final InvitationApiService _invitationApiService;
  final StreamController<List<Invitation>> _invitationsController;
  final StreamController<List<JourneyParticipant>> _participantsController;
  Timer? _realTimeTimer;

  InvitationRepositoryImpl(this._invitationApiService)
      : _invitationsController = StreamController<List<Invitation>>.broadcast(),
        _participantsController = StreamController<List<JourneyParticipant>>.broadcast();

  @override
  Stream<List<Invitation>> get invitationsStream => _invitationsController.stream;

  @override
  Stream<List<JourneyParticipant>> get participantsStream => _participantsController.stream;

  @override
  Future<Result<List<User>>> searchUsers(String query) async {
    try {
      final responseData = await _invitationApiService.searchUsers(
        query: query,
        limit: 10,
      );
      
      final usersData = responseData['data'] as List<dynamic>;
      final users = usersData
          .map((json) => User(
                id: json['id'] as String,
                email: json['email'] as String,
                displayName: json['displayName'] as String,
                avatarUrl: json['avatarUrl'] as String?,
              ))
          .toList();
      
      return ResultHelper.success(users);
    } catch (e) {
      return ResultHelper.failure(
        NetworkFailure(message: 'Failed to search users: ${e.toString()}'),
      );
    }
  }

  @override
  Future<Result<Invitation>> sendInvitation({
    required String journeyId,
    required String inviteeId,
    String? message,
  }) async {
    try {
      final responseData = await _invitationApiService.sendInvitation(
        journeyId: journeyId,
        invitationData: {
          'inviteeId': inviteeId,
          if (message != null) 'message': message,
        },
      );
      
      final invitationData = responseData['data'] as Map<String, dynamic>;
      final invitation = _parseInvitation(invitationData);
      
      // Refresh invitations list
      await _fetchInvitations(journeyId);
      
      return ResultHelper.success(invitation);
    } catch (e) {
      return ResultHelper.failure(
        NetworkFailure(message: 'Failed to send invitation: ${e.toString()}'),
      );
    }
  }

  @override
  Future<Result<Invitation>> respondToInvitation({
    required String invitationId,
    required bool accept,
  }) async {
    try {
      final responseData = await _invitationApiService.respondToInvitation(
        invitationId: invitationId,
        responseData: {
          'response': accept ? 'accept' : 'decline',
        },
      );
      
      final invitationData = responseData['data'] as Map<String, dynamic>;
      final invitation = _parseInvitation(invitationData);
      
      // Refresh both invitations and participants
      final journeyId = invitation.journeyId;
      await Future.wait([
        _fetchInvitations(journeyId),
        _fetchParticipants(journeyId),
      ]);
      
      return ResultHelper.success(invitation);
    } catch (e) {
      return ResultHelper.failure(
        NetworkFailure(message: 'Failed to respond to invitation: ${e.toString()}'),
      );
    }
  }

  @override
  Future<Result<List<Invitation>>> getInvitations(String journeyId) async {
    try {
      final responseData = await _invitationApiService.getJourneyInvitations(journeyId);
      
      final invitationsData = responseData['data'] as List<dynamic>;
      final invitations = invitationsData
          .map((json) => _parseInvitation(json as Map<String, dynamic>))
          .toList();
      
      _invitationsController.add(invitations);
      
      return ResultHelper.success(invitations);
    } catch (e) {
      return ResultHelper.failure(
        NetworkFailure(message: 'Failed to fetch invitations: ${e.toString()}'),
      );
    }
  }

  @override
  Future<Result<List<JourneyParticipant>>> getParticipants(String journeyId) async {
    try {
      // TODO: Use proper participants endpoint when available
      // For now, return empty list as this needs proper participant endpoint implementation
      final participants = <JourneyParticipant>[];
      
      _participantsController.add(participants);
      
      return ResultHelper.success(participants);
    } catch (e) {
      return ResultHelper.failure(
        NetworkFailure(message: 'Failed to fetch participants: ${e.toString()}'),
      );
    }
  }

  @override
  Future<Result<void>> removeParticipant({
    required String journeyId,
    required String participantId,
  }) async {
    try {
      // TODO: Use proper remove participant endpoint when available
      throw UnimplementedError(
          'Remove participant needs journey API service integration');
    } catch (e) {
      return ResultHelper.failure(
        NetworkFailure(message: 'Failed to remove participant: ${e.toString()}'),
      );
    }
  }

  @override
  Future<Result<void>> cancelInvitation(String invitationId) async {
    try {
      await _invitationApiService.cancelInvitation(invitationId);
      
      return ResultHelper.success(null);
    } catch (e) {
      return ResultHelper.failure(
        NetworkFailure(message: 'Failed to cancel invitation: ${e.toString()}'),
      );
    }
  }

  @override
  void startRealTimeUpdates(String journeyId) {
    // TODO: Implement WebSocket connection for real-time updates
    // For now, use periodic polling
    _realTimeTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _fetchInvitations(journeyId);
      _fetchParticipants(journeyId);
    });
  }

  @override
  void stopRealTimeUpdates() {
    _realTimeTimer?.cancel();
    _realTimeTimer = null;
  }

  /// Private helper to fetch invitations and update stream
  Future<void> _fetchInvitations(String journeyId) async {
    final result = await getInvitations(journeyId);
    if (result.isSuccess) {
      _invitationsController.add(result.data!);
    }
  }

  /// Private helper to fetch participants and update stream
  Future<void> _fetchParticipants(String journeyId) async {
    final result = await getParticipants(journeyId);
    if (result.isSuccess) {
      _participantsController.add(result.data!);
    }
  }

  /// Parse invitation from JSON
  Invitation _parseInvitation(Map<String, dynamic> json) {
    return Invitation(
      id: json['id'] as String,
      journeyId: json['journeyId'] as String,
      inviterId: json['inviterId'] as String,
      inviteeId: json['inviteeId'] as String,
      inviteeEmail: json['inviteeEmail'] as String,
      inviteeName: json['inviteeName'] as String?,
      inviteeAvatarUrl: json['inviteeAvatarUrl'] as String?,
      status: _parseInvitationStatus(json['status'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      respondedAt: json['respondedAt'] != null
          ? DateTime.parse(json['respondedAt'] as String)
          : null,
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : null,
      message: json['message'] as String?,
    );
  }

  /// Parse invitation status from string
  InvitationStatus _parseInvitationStatus(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return InvitationStatus.pending;
      case 'accepted':
        return InvitationStatus.accepted;
      case 'declined':
        return InvitationStatus.declined;
      case 'expired':
        return InvitationStatus.expired;
      case 'cancelled':
        return InvitationStatus.cancelled;
      default:
        return InvitationStatus.pending;
    }
  }

  /// Dispose resources
  void dispose() {
    _realTimeTimer?.cancel();
    _invitationsController.close();
    _participantsController.close();
  }
}