import 'package:hive/hive.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../domain/entities/user_entity.dart';

part 'user_model.g.dart';

/// User model for data layer
/// Handles JSON serialization and Hive storage
@JsonSerializable()
@HiveType(typeId: 0)
class UserModel extends UserEntity {
  UserModel({
    required this.id,
    required this.email,
    required this.name,
    this.profilePicture,
    this.isEmailVerified = false,
    required this.createdAt,
    this.updatedAt,
  }) : super(
          id: id,
          email: email,
          name: name,
          profilePicture: profilePicture,
          isEmailVerified: isEmailVerified,
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

  @HiveField(0)
  @override
  final String id;

  @HiveField(1)
  @override
  final String email;

  @HiveField(2)
  @override
  final String name;

  @HiveField(3)
  @override
  final String? profilePicture;

  @HiveField(4)
  @override
  final bool isEmailVerified;

  @HiveField(5)
  @override
  final DateTime createdAt;

  @HiveField(6)
  @override
  final DateTime? updatedAt;

  /// Create UserModel from JSON
  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'] as String,
        email: json['email'] as String,
        name: json['name'] as String,
        profilePicture: json['profilePicture'] as String?,
        isEmailVerified: json['isEmailVerified'] as bool? ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: json['updatedAt'] != null 
            ? DateTime.parse(json['updatedAt'] as String)
            : null,
      );

  /// Convert UserModel to JSON
  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'profilePicture': profilePicture,
        'isEmailVerified': isEmailVerified,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  /// Convert UserModel to UserEntity
  UserEntity toEntity() => UserEntity(
        id: id,
        email: email,
        name: name,
        profilePicture: profilePicture,
        isEmailVerified: isEmailVerified,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  /// Create UserModel from UserEntity
  factory UserModel.fromEntity(UserEntity entity) => UserModel(
        id: entity.id,
        email: entity.email,
        name: entity.name,
        profilePicture: entity.profilePicture,
        isEmailVerified: entity.isEmailVerified,
        createdAt: entity.createdAt,
        updatedAt: entity.updatedAt,
      );

  /// Create a copy with new values
  @override
  UserModel copyWith({
    String? id,
    String? email,
    String? name,
    String? profilePicture,
    bool? isEmailVerified,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserModel(
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