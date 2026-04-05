import 'package:equatable/equatable.dart';

enum InvitationStatus { 
  pending, 
  accepted, 
  declined, 
  expired,
  cancelled 
}

enum ParticipantRole { 
  leader, 
  participant 
}

enum ParticipantStatus { 
  invited,
  accepted, 
  active, 
  disconnected,
  left 
}

class Invitation extends Equatable {
  final String id;
  final String journeyId;
  final String inviterId;
  final String inviteeId;
  final String inviteeEmail;
  final String? inviteeName;
  final String? inviteeAvatarUrl;
  final InvitationStatus status;
  final DateTime createdAt;
  final DateTime? respondedAt;
  final DateTime? expiresAt;
  final String? message;

  const Invitation({
    required this.id,
    required this.journeyId,
    required this.inviterId,
    required this.inviteeId,
    required this.inviteeEmail,
    this.inviteeName,
    this.inviteeAvatarUrl,
    required this.status,
    required this.createdAt,
    this.respondedAt,
    this.expiresAt,
    this.message,
  });

  Invitation copyWith({
    String? id,
    String? journeyId,
    String? inviterId,
    String? inviteeId,
    String? inviteeEmail,
    String? inviteeName,
    String? inviteeAvatarUrl,
    InvitationStatus? status,
    DateTime? createdAt,
    DateTime? respondedAt,
    DateTime? expiresAt,
    String? message,
  }) {
    return Invitation(
      id: id ?? this.id,
      journeyId: journeyId ?? this.journeyId,
      inviterId: inviterId ?? this.inviterId,
      inviteeId: inviteeId ?? this.inviteeId,
      inviteeEmail: inviteeEmail ?? this.inviteeEmail,
      inviteeName: inviteeName ?? this.inviteeName,
      inviteeAvatarUrl: inviteeAvatarUrl ?? this.inviteeAvatarUrl,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      respondedAt: respondedAt ?? this.respondedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      message: message ?? this.message,
    );
  }

  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  bool get isPending {
    return status == InvitationStatus.pending && !isExpired;
  }

  @override
  List<Object?> get props => [
        id,
        journeyId,
        inviterId,
        inviteeId,
        inviteeEmail,
        inviteeName,
        inviteeAvatarUrl,
        status,
        createdAt,
        respondedAt,
        expiresAt,
        message,
      ];
}

class JourneyParticipant extends Equatable {
  final String id;
  final String userId;
  final String journeyId;
  final String displayName;
  final String email;
  final String? avatarUrl;
  final ParticipantRole role;
  final ParticipantStatus status;
  final String? invitationId;
  final DateTime? joinedAt;
  final DateTime? lastSeenAt;
  final Map<String, dynamic>? metadata; // Vehicle info, etc.

  const JourneyParticipant({
    required this.id,
    required this.userId,
    required this.journeyId,
    required this.displayName,
    required this.email,
    this.avatarUrl,
    required this.role,
    required this.status,
    this.invitationId,
    this.joinedAt,
    this.lastSeenAt,
    this.metadata,
  });

  JourneyParticipant copyWith({
    String? id,
    String? userId,
    String? journeyId,
    String? displayName,
    String? email,
    String? avatarUrl,
    ParticipantRole? role,
    ParticipantStatus? status,
    String? invitationId,
    DateTime? joinedAt,
    DateTime? lastSeenAt,
    Map<String, dynamic>? metadata,
  }) {
    return JourneyParticipant(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      journeyId: journeyId ?? this.journeyId,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
      status: status ?? this.status,
      invitationId: invitationId ?? this.invitationId,
      joinedAt: joinedAt ?? this.joinedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      metadata: metadata ?? this.metadata,
    );
  }

  bool get isLeader => role == ParticipantRole.leader;
  bool get isActive => status == ParticipantStatus.active;
  bool get isOnline => lastSeenAt != null && 
      DateTime.now().difference(lastSeenAt!).inMinutes < 5;

  String get initials {
    final names = displayName.split(' ');
    if (names.length >= 2) {
      return '${names[0][0]}${names[1][0]}'.toUpperCase();
    } else if (names.isNotEmpty) {
      return names[0][0].toUpperCase();
    }
    return 'U';
  }

  int get vehicleNumber {
    return metadata?['vehicleNumber'] as int? ?? 1;
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        journeyId,
        displayName,
        email,
        avatarUrl,
        role,
        status,
        invitationId,
        joinedAt,
        lastSeenAt,
        metadata,
      ];
}

class User extends Equatable {
  final String id;
  final String email;
  final String displayName;
  final String? avatarUrl;
  final DateTime? lastSeenAt;

  const User({
    required this.id,
    required this.email,
    required this.displayName,
    this.avatarUrl,
    this.lastSeenAt,
  });

  @override
  List<Object?> get props => [
        id,
        email,
        displayName,
        avatarUrl,
        lastSeenAt,
      ];
}