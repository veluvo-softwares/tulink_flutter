import 'package:json_annotation/json_annotation.dart';

part 'auth_tokens_model.g.dart';

/// Authentication tokens model for API responses
/// Handles the tokens object from the auth API
@JsonSerializable()
class AuthTokensModel {
  /// Creates an auth tokens model
  const AuthTokensModel({
    required this.idToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  /// Factory constructor from JSON
  factory AuthTokensModel.fromJson(Map<String, dynamic> json) =>
      _$AuthTokensModelFromJson(json);

  /// Firebase ID token (JWT)
  final String idToken;

  /// Firebase refresh token
  final String refreshToken;

  /// Token expiration time in seconds
  final int expiresIn;

  /// Converts to JSON
  Map<String, dynamic> toJson() => _$AuthTokensModelToJson(this);

  @override
  String toString() {
    return 'AuthTokensModel(idToken: ${idToken.substring(0, 20)}..., '
        'refreshToken: ${refreshToken.substring(0, 20)}..., '
        'expiresIn: $expiresIn)';
  }
}
