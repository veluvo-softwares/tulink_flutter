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
    this.phoneNumber,
    this.profilePicture,
    this.isEmailVerified = false,
    required this.createdAt,
    this.updatedAt,
  }) : super(
          id: id,
          email: email,
          name: name,
          phoneNumber: phoneNumber,
          profilePicture: profilePicture,
          isEmailVerified: isEmailVerified,
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

  @HiveField(0)
  @JsonKey(name: 'uid')
  @override
  final String id;

  @HiveField(1)
  @override
  final String email;

  @HiveField(2)
  @JsonKey(name: 'displayName')
  @override
  final String name;

  @HiveField(3)
  @override
  final String? phoneNumber;

  @HiveField(4)
  @override
  final String? profilePicture;

  @HiveField(5)
  @JsonKey(name: 'emailVerified')
  @override
  final bool isEmailVerified;

  @HiveField(6)
  @override
  final DateTime createdAt;

  @HiveField(7)
  @override
  final DateTime? updatedAt;

  /// Create UserModel from JSON with robust error handling
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['uid']?.toString() ?? json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      name: json['displayName']?.toString() ?? json['name']?.toString() ?? '',
      phoneNumber: json['phoneNumber']?.toString(),
      profilePicture: json['profilePicture']?.toString() ?? 
                      json['photoURL']?.toString(),
      isEmailVerified: json['emailVerified'] as bool? ?? 
                      json['email_verified'] as bool? ?? false,
      createdAt: _parseCreatedAt(json),
      updatedAt: _parseUpdatedAt(json),
    );
  }

  /// Parse createdAt from various possible structures
  static DateTime _parseCreatedAt(Map<String, dynamic> json) {
    // Direct field
    if (json['createdAt'] != null) {
      final parsed = DateTime.tryParse(json['createdAt'].toString());
      if (parsed != null) return parsed;
    }
    
    // Firebase metadata structure
    if (json['metadata'] != null) {
      final metadata = json['metadata'] as Map<String, dynamic>;
      if (metadata['creationTime'] != null) {
        final parsed = DateTime.tryParse(metadata['creationTime'].toString());
        if (parsed != null) return parsed;
      }
    }
    
    // Fallback alternatives
    if (json['created_at'] != null) {
      final parsed = DateTime.tryParse(json['created_at'].toString());
      if (parsed != null) return parsed;
    }
    
    // Default to current time
    return DateTime.now();
  }

  /// Parse updatedAt from various possible structures  
  static DateTime? _parseUpdatedAt(Map<String, dynamic> json) {
    // Direct field
    if (json['updatedAt'] != null) {
      return DateTime.tryParse(json['updatedAt'].toString());
    }
    
    // Firebase metadata structure
    if (json['metadata'] != null) {
      final metadata = json['metadata'] as Map<String, dynamic>;
      if (metadata['lastSignInTime'] != null) {
        return DateTime.tryParse(metadata['lastSignInTime'].toString());
      }
    }
    
    // Fallback alternatives
    if (json['updated_at'] != null) {
      return DateTime.tryParse(json['updated_at'].toString());
    }
    
    return null;
  }

  /// Create UserModel from UserEntity
  factory UserModel.fromEntity(UserEntity entity) => UserModel(
        id: entity.id,
        email: entity.email,
        name: entity.name,
        phoneNumber: entity.phoneNumber,
        profilePicture: entity.profilePicture,
        isEmailVerified: entity.isEmailVerified,
        createdAt: entity.createdAt,
        updatedAt: entity.updatedAt,
      );

  /// Convert UserModel to JSON (uses generated method with JsonKey mappings)
  Map<String, dynamic> toJson() => _$UserModelToJson(this);

  /// Convert UserModel to UserEntity
  UserEntity toEntity() => UserEntity(
        id: id,
        email: email,
        name: name,
        phoneNumber: phoneNumber,
        profilePicture: profilePicture,
        isEmailVerified: isEmailVerified,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  /// Create a copy with new values
  @override
  UserModel copyWith({
    String? id,
    String? email,
    String? name,
    String? phoneNumber,
    String? profilePicture,
    bool? isEmailVerified,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserModel(
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
