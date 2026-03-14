import 'package:json_annotation/json_annotation.dart';
import 'package:tulink_flutter/features/auth/data/models/auth_tokens_model.dart';
import 'package:tulink_flutter/features/auth/data/models/user_model.dart';

part 'auth_response_model.g.dart';

/// Authentication response data model
/// Represents the 'data' object in successful auth API responses
@JsonSerializable()
class AuthResponseModel {
  /// Creates an auth response model
  const AuthResponseModel({
    required this.user,
    required this.tokens,
  });

  /// Factory constructor from JSON
  factory AuthResponseModel.fromJson(Map<String, dynamic> json) {
    return AuthResponseModel(
      user: UserModel.fromJson(json['user'] as Map<String, dynamic>),
      tokens: AuthTokensModel.fromJson(json['tokens'] as Map<String, dynamic>),
    );
  }

  /// User information from Firebase Auth
  final UserModel user;

  /// Authentication tokens
  final AuthTokensModel tokens;

  /// Converts to JSON
  Map<String, dynamic> toJson() => _$AuthResponseModelToJson(this);

  @override
  String toString() {
    return 'AuthResponseModel(user: $user, tokens: $tokens)';
  }
}
