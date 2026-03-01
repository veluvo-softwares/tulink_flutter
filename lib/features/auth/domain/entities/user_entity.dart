import 'package:equatable/equatable.dart';

/// User entity representing the core business logic model
class UserEntity extends Equatable {
  const UserEntity({
    required this.id,
    required this.email,
    required this.name,
    this.profilePicture,
    this.isEmailVerified = false,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String email;
  final String name;
  final String? profilePicture;
  final bool isEmailVerified;
  final DateTime createdAt;
  final DateTime? updatedAt;

  @override
  List<Object?> get props => [
        id,
        email,
        name,
        profilePicture,
        isEmailVerified,
        createdAt,
        updatedAt,
      ];

  UserEntity copyWith({
    String? id,
    String? email,
    String? name,
    String? profilePicture,
    bool? isEmailVerified,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserEntity(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      profilePicture: profilePicture ?? this.profilePicture,
      isEmailVerified: isEmailVerified ?? this.isEmailVerified,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}