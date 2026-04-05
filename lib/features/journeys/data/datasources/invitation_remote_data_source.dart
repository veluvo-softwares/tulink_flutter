import 'package:tulink_flutter/features/journeys/domain/entities/invitation.dart';
import 'package:tulink_flutter/features/journeys/data/services/invitation_api_service.dart';

/// Remote data source for invitations
/// Now focuses purely on executing service calls and mapping results to
/// Domain Entities
/// Zero hardcoded strings - all endpoints are defined in InvitationApiService
abstract class InvitationRemoteDataSource {
  /// Search for users to invite
  Future<List<User>> searchUsers(String query);
  
  /// Send invitation to join a journey
  Future<Invitation> sendInvitation({
    required String journeyId,
    required String inviteeId,
    String? message,
  });
  
  /// Respond to an invitation (accept/decline)
  Future<Invitation> respondToInvitation({
    required String invitationId,
    required bool accept,
  });
  
  /// Get invitations for a journey
  Future<List<Invitation>> getJourneyInvitations(String journeyId);
  
  /// Get participants for a journey
  Future<List<JourneyParticipant>> getJourneyParticipants(String journeyId);
  
  /// Remove a participant from a journey
  Future<void> removeParticipant({
    required String journeyId,
    required String participantId,
  });
  
  /// Cancel an invitation
  Future<void> cancelInvitation(String invitationId);

  /// Get user's received invitations
  Future<List<Invitation>> getMyInvitations();

  /// Get pending invitations for user
  Future<List<Invitation>> getPendingInvitations();

  /// Get sent invitations from user
  Future<List<Invitation>> getSentInvitations();

  /// Get invitation by ID
  Future<Invitation> getInvitationById(String invitationId);

  /// Resend an invitation
  Future<Invitation> resendInvitation(String invitationId);
}

/// Implementation of InvitationRemoteDataSource using InvitationApiService
/// Pure data mapping layer with no business logic
/// Single responsibility: Execute API calls and map responses to domain
/// entities
class InvitationRemoteDataSourceImpl implements InvitationRemoteDataSource {
  /// Constructor takes InvitationApiService dependency
  InvitationRemoteDataSourceImpl(this._invitationApiService);

  final InvitationApiService _invitationApiService;

  @override
  Future<List<User>> searchUsers(String query) async {
    // Execute API call using standardized response
    final responseData = await _invitationApiService.searchUsers(
      query: query,
      limit: 10,
    );
    
    // Parse the response data
    final usersData = responseData['data'] as List<dynamic>;
    return usersData
        .map((json) => User(
              id: json['id'] as String,
              email: json['email'] as String,
              displayName: json['displayName'] as String,
              avatarUrl: json['avatarUrl'] as String?,
            ))
        .toList();
  }

  @override
  Future<Invitation> sendInvitation({
    required String journeyId,
    required String inviteeId,
    String? message,
  }) async {
    // Execute API call through service
    final responseData = await _invitationApiService.sendInvitation(
      journeyId: journeyId,
      invitationData: {
        'inviteeId': inviteeId,
        if (message != null) 'message': message,
      },
    );

    // Parse the response data
    final invitationData = responseData['data'] as Map<String, dynamic>;
    return _parseInvitation(invitationData);
  }

  @override
  Future<Invitation> respondToInvitation({
    required String invitationId,
    required bool accept,
  }) async {
    // Execute API call using standardized response
    final responseData = await _invitationApiService.respondToInvitation(
      invitationId: invitationId,
      responseData: {
        'response': accept ? 'accept' : 'decline',
      },
    );
    
    // Parse the response data
    final invitationData = responseData['data'] as Map<String, dynamic>;
    return _parseInvitation(invitationData);
  }

  @override
  Future<List<Invitation>> getJourneyInvitations(String journeyId) async {
    // Execute API call using standardized response
    final responseData = await _invitationApiService.getJourneyInvitations(journeyId);
    
    // Parse the response data
    final invitationsData = responseData['data'] as List<dynamic>;
    return invitationsData
        .map((json) => _parseInvitation(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<JourneyParticipant>> getJourneyParticipants(
      String journeyId) async {
    // TODO: Use journey API service for participant data when available
    // This will need proper implementation with dedicated participant endpoint
    
    // For now, return empty list as this needs proper participant endpoint
    return <JourneyParticipant>[];
  }

  @override
  Future<void> removeParticipant({
    required String journeyId,
    required String participantId,
  }) async {
    // This would typically be handled by the journey API service
    // For now, we'll create a direct call
    throw UnimplementedError(
        'Remove participant needs journey API service integration');
  }

  @override
  Future<void> cancelInvitation(String invitationId) async {
    // Direct delegation to service
    await _invitationApiService.cancelInvitation(invitationId);
  }

  @override
  Future<List<Invitation>> getMyInvitations() async {
    // Execute API call using standardized response
    final responseData = await _invitationApiService.getMyInvitations();
    
    // Parse the response data
    final invitationsData = responseData['data'] as List<dynamic>;
    return invitationsData
        .map((json) => _parseInvitation(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<Invitation>> getPendingInvitations() async {
    // Execute API call using standardized response
    final responseData = await _invitationApiService.getPendingInvitations();
    
    // Parse the response data
    final invitationsData = responseData['data'] as List<dynamic>;
    return invitationsData
        .map((json) => _parseInvitation(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<Invitation>> getSentInvitations() async {
    // Execute API call using standardized response
    final responseData = await _invitationApiService.getSentInvitations();
    
    // Parse the response data
    final invitationsData = responseData['data'] as List<dynamic>;
    return invitationsData
        .map((json) => _parseInvitation(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Invitation> getInvitationById(String invitationId) async {
    // Execute API call using standardized response
    final responseData = await _invitationApiService.getInvitationById(invitationId);
    
    // Parse the response data
    final invitationData = responseData['data'] as Map<String, dynamic>;
    return _parseInvitation(invitationData);
  }

  @override
  Future<Invitation> resendInvitation(String invitationId) async {
    // Execute API call using standardized response
    final responseData = await _invitationApiService.resendInvitation(invitationId);
    
    // Parse the response data
    final invitationData = responseData['data'] as Map<String, dynamic>;
    return _parseInvitation(invitationData);
  }

  /// Private helper to parse invitation JSON to domain entity
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
}
