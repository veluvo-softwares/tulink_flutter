import 'package:tulink_flutter/features/invites/domain/entities/user_search_result.dart';

class UserSearchResultModel extends UserSearchResult {
  const UserSearchResultModel({
    required super.uid,
    required super.email,
    required super.displayName,
    super.phoneNumber,
  });

  factory UserSearchResultModel.fromJson(Map<String, dynamic> json) {
    return UserSearchResultModel(
      uid: json['uid']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      phoneNumber: json['phoneNumber']?.toString(),
    );
  }
}
