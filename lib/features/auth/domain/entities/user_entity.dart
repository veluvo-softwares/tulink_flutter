import 'package:equatable/equatable.dart';

/// User entity representing the core business logic model
class UserEntity extends Equatable {
  const UserEntity({
    required this.id,
    required this.email,
    required this.name,
    this.phoneNumber,
    this.profilePicture,
    this.isEmailVerified = false,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String email;
  final String name;
  final String? phoneNumber;
  final String? profilePicture;
  final bool isEmailVerified;
  final DateTime createdAt;
  final DateTime? updatedAt;

  @override
  List<Object?> get props => [
        id,
        email,
        name,
        phoneNumber,
        profilePicture,
        isEmailVerified,
        createdAt,
        updatedAt,
      ];

  /// Create a copy of this entity with updated fields
  UserEntity copyWith({
    String? id,
    String? email,
    String? name,
    String? phoneNumber,
    String? profilePicture,
    bool? isEmailVerified,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserEntity(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      profilePicture: profilePicture ?? this.profilePicture,
      isEmailVerified: isEmailVerified ?? this.isEmailVerified,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
