import '../../../../core/errors/failure.dart';
import '../entities/user_entity.dart';

/// Authentication repository interface
/// This defines the contract for authentication operations
/// The implementation will be in the data layer
abstract class AuthRepository {
  /// Sign in with email and password
  Future<({UserEntity? user, String? token, Failure? failure})> signIn({
    required String email,
    required String password,
  });

  /// Sign up with email, password and name
  Future<({UserEntity? user, String? token, Failure? failure})> signUp({
    required String email,
    required String password,
    required String name,
  });

  /// Sign out the current user
  Future<({bool success, Failure? failure})> signOut();

  /// Get currently signed in user
  Future<({UserEntity? user, Failure? failure})> getCurrentUser();

  /// Check if user is signed in
  Future<bool> isSignedIn();

  /// Refresh authentication token
  Future<({String? token, Failure? failure})> refreshToken();

  /// Send password reset email
  Future<({bool success, Failure? failure})> resetPassword({
    required String email,
  });

  /// Verify email address
  Future<({bool success, Failure? failure})> verifyEmail({
    required String token,
  });

  /// Update user profile
  Future<({UserEntity? user, Failure? failure})> updateProfile({
    String? name,
    String? profilePicture,
  });

  /// Delete user account
  Future<({bool success, Failure? failure})> deleteAccount();
}