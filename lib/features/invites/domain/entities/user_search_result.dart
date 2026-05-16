import 'package:equatable/equatable.dart';

class UserSearchResult extends Equatable {
  final String uid;
  final String email;
  final String displayName;
  final String? phoneNumber;

  const UserSearchResult({
    required this.uid,
    required this.email,
    required this.displayName,
    this.phoneNumber,
  });

  @override
  List<Object?> get props => [uid, email, displayName, phoneNumber];
}
