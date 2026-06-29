import '../../../../core/errors/failure.dart';
import '../../../../core/network/dio_client.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_local_data_source.dart';
import '../datasources/auth_remote_data_source.dart';
import '../models/user_model.dart';
import '../services/social_auth_service.dart';

/// Implementation of AuthRepository
/// Follows the Repository Pattern with Clean Architecture
/// Demonstrates: Check cache -> If empty, fetch from API -> Save to cache
class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
    required this.dioClient,
    required this.socialAuthService,
  });


  final AuthRemoteDataSource remoteDataSource;
  final AuthLocalDataSource localDataSource;
  final DioClient dioClient;
  final SocialAuthService socialAuthService;

  @override
  Future<({UserEntity? user, String? token, Failure? failure})> signIn({
    required String email,
    required String password,
  }) async {
    print('🚀 AuthRepositoryImpl.signIn() called with email: $email');
    try {
      print('📞 Calling remoteDataSource.signIn()...');
      // Attempt remote sign in
      final result = await remoteDataSource.signIn(
        email: email,
        password: password,
      );
      print('✅ RemoteDataSource.signIn() returned successfully');

      // Cache the user and token locally
      await localDataSource.cacheUser(result.user);
      await localDataSource.cacheToken(result.token);
      await dioClient.saveAuthToken(result.token);
      
      // Save refresh token if provided
      if (result.refreshToken != null) {
        print('🔑 Refresh token being saved: ${result.refreshToken}');
        await dioClient.saveRefreshToken(result.refreshToken!);
        print('✅ Refresh token save operation completed');
      } else {
        print('⚠️ No refresh token provided in API response');
      }

      return (
        user: result.user.toEntity(),
        token: result.token,
        failure: null,
      );
    } on Failure catch (failure) {
      print('❌ AuthRepositoryImpl.signIn() caught Failure: $failure');
      return (user: null, token: null, failure: failure);
    } catch (e) {
      print('❌ AuthRepositoryImpl.signIn() caught exception: $e');
      return (
        user: null,
        token: null,
        failure: const ServerFailure(message: 'Sign in failed'),
      );
    }
  }

  @override
  Future<({UserEntity? user, String? token, Failure? failure})> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      // Attempt remote sign up
      final result = await remoteDataSource.signUp(
        email: email,
        password: password,
        name: name,
      );

      // Cache the user and token locally
      await localDataSource.cacheUser(result.user);
      await localDataSource.cacheToken(result.token);
      await dioClient.saveAuthToken(result.token);
      
      // Save refresh token if provided
      if (result.refreshToken != null) {
        print('🔑 Refresh token being saved: ${result.refreshToken}');
        await dioClient.saveRefreshToken(result.refreshToken!);
        print('✅ Refresh token save operation completed');
      } else {
        print('⚠️ No refresh token provided in API response');
      }

      return (
        user: result.user.toEntity(),
        token: result.token,
        failure: null,
      );
    } on Failure catch (failure) {
      return (user: null, token: null, failure: failure);
    } catch (e) {
      return (
        user: null,
        token: null,
        failure: const ServerFailure(message: 'Sign up failed'),
      );
    }
  }

  @override
  Future<({UserEntity? user, String? token, Failure? failure})>
      signInWithGoogle() async {
    try {
      final google = await socialAuthService.google();
      final result = await remoteDataSource.signInWithSocial(
        provider: 'google',
        idToken: google.idToken,
        displayName: google.displayName,
      );
      return _persistSocialSession(result);
    } on SocialSignInCancelled {
      // User backed out — surface a benign sentinel so the provider stays quiet.
      return (user: null, token: null, failure: AuthFailure.cancelled);
    } on Failure catch (failure) {
      return (user: null, token: null, failure: failure);
    } catch (e) {
      return (
        user: null,
        token: null,
        failure: const ServerFailure(message: 'Google sign-in failed'),
      );
    }
  }

  @override
  Future<({UserEntity? user, String? token, Failure? failure})>
      signInWithApple() async {
    try {
      final apple = await socialAuthService.apple();
      final result = await remoteDataSource.signInWithSocial(
        provider: 'apple',
        idToken: apple.idToken,
        nonce: apple.rawNonce,
        displayName: apple.displayName,
      );
      return _persistSocialSession(result);
    } on SocialSignInCancelled {
      return (user: null, token: null, failure: AuthFailure.cancelled);
    } on Failure catch (failure) {
      return (user: null, token: null, failure: failure);
    } catch (e) {
      return (
        user: null,
        token: null,
        failure: const ServerFailure(message: 'Apple sign-in failed'),
      );
    }
  }

  /// Shared caching block for a successful social exchange — mirrors signIn().
  Future<({UserEntity? user, String? token, Failure? failure})>
      _persistSocialSession(
    ({UserModel user, String token, String? refreshToken}) result,
  ) async {
    await localDataSource.cacheUser(result.user);
    await localDataSource.cacheToken(result.token);
    await dioClient.saveAuthToken(result.token);

    if (result.refreshToken != null) {
      await dioClient.saveRefreshToken(result.refreshToken!);
    }

    return (
      user: result.user.toEntity(),
      token: result.token,
      failure: null,
    );
  }

  @override
  Future<({bool success, Failure? failure})> signOut() async {
    try {
      // Attempt remote sign out (optional, can continue if fails)
      try {
        await remoteDataSource.signOut();
      } catch (e) {
        // Continue with local sign out even if remote fails
      }

      // Clear local cache and tokens
      await localDataSource.clearCachedUser();
      await localDataSource.clearCachedToken();
      await dioClient.clearTokens();

      return (success: true, failure: null);
    } on Failure catch (failure) {
      return (success: false, failure: failure);
    } catch (e) {
      return (
        success: false,
        failure: const ServerFailure(message: 'Sign out failed'),
      );
    }
  }

  @override
  Future<({UserEntity? user, Failure? failure})> getCurrentUser() async {
    try {
      // First, try to get user from cache
      final cachedUser = await localDataSource.getCachedUser();
      if (cachedUser != null) {
        return (user: cachedUser.toEntity(), failure: null);
      }

      // If no cached user, try to get from remote
      final user = await remoteDataSource.getCurrentUser();
      
      // Cache the user for future use
      await localDataSource.cacheUser(user);

      return (user: user.toEntity(), failure: null);
    } on Failure catch (failure) {
      return (user: null, failure: failure);
    } catch (e) {
      return (
        user: null,
        failure: const ServerFailure(message: 'Failed to get current user'),
      );
    }
  }

  @override
  Future<bool> isSignedIn() async {
    try {
      // Check if user is cached locally
      final isUserCached = await localDataSource.isUserCached();
      if (!isUserCached) return false;

      // A currently-valid (unexpired) access token means we're good.
      final token = await dioClient.getAuthToken();
      if (token != null && token.isNotEmpty) return true;

      // Access token is missing or expired. This is the common case when iOS
      // relaunches a backgrounded app after the ~1h ID-token lifetime — the
      // session is still alive as long as we hold a refresh token. Recover it
      // here instead of dropping the user at the login screen.
      // tryRefreshToken() persists the rotated tokens; on a genuine failure it
      // clears tokens and fires onAuthLost, so returning false is safe.
      final hasRefresh = await dioClient.hasRefreshToken();
      if (!hasRefresh) return false;
      final fresh = await dioClient.tryRefreshToken();
      return fresh != null && fresh.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<({String? token, Failure? failure})> refreshToken() async {
    try {
      final newToken = await remoteDataSource.refreshToken();
      
      // Save the new token
      await localDataSource.cacheToken(newToken);
      await dioClient.saveAuthToken(newToken);

      return (token: newToken, failure: null);
    } on Failure catch (failure) {
      return (token: null, failure: failure);
    } catch (e) {
      return (
        token: null,
        failure: const ServerFailure(message: 'Token refresh failed'),
      );
    }
  }

  @override
  Future<({bool success, Failure? failure})> resetPassword({
    required String email,
  }) async {
    try {
      await remoteDataSource.resetPassword(email: email);
      return (success: true, failure: null);
    } on Failure catch (failure) {
      return (success: false, failure: failure);
    } catch (e) {
      return (
        success: false,
        failure: const ServerFailure(message: 'Password reset failed'),
      );
    }
  }

  @override
  Future<({bool success, Failure? failure})> verifyEmail({
    required String token,
  }) async {
    try {
      await remoteDataSource.verifyEmail(token: token);
      return (success: true, failure: null);
    } on Failure catch (failure) {
      return (success: false, failure: failure);
    } catch (e) {
      return (
        success: false,
        failure: const ServerFailure(message: 'Email verification failed'),
      );
    }
  }

  @override
  Future<({UserEntity? user, Failure? failure})> updateProfile({
    String? name,
    String? profilePicture,
  }) async {
    try {
      final updatedUser = await remoteDataSource.updateProfile(
        name: name,
        profilePicture: profilePicture,
      );

      // Update cached user
      await localDataSource.cacheUser(updatedUser);

      return (user: updatedUser.toEntity(), failure: null);
    } on Failure catch (failure) {
      return (user: null, failure: failure);
    } catch (e) {
      return (
        user: null,
        failure: const ServerFailure(message: 'Profile update failed'),
      );
    }
  }

  @override
  Future<({bool success, Failure? failure})> deleteAccount() async {
    try {
      await remoteDataSource.deleteAccount();

      // Clear all local data
      await localDataSource.clearCachedUser();
      await localDataSource.clearCachedToken();
      await dioClient.clearTokens();

      return (success: true, failure: null);
    } on Failure catch (failure) {
      return (success: false, failure: failure);
    } catch (e) {
      return (
        success: false,
        failure: const ServerFailure(message: 'Account deletion failed'),
      );
    }
  }

  @override
  Future<({bool success, Failure? failure})> sendEmailVerification() async {
    try {
      await remoteDataSource.sendEmailVerification();
      return (success: true, failure: null);
    } on Failure catch (failure) {
      return (success: false, failure: failure);
    } catch (e) {
      return (
        success: false,
        failure: const ServerFailure(message: 'Failed to send verification email'),
      );
    }
  }

  @override
  Future<({bool isEmailVerified, Failure? failure})> checkEmailVerification() async {
    try {
      final result = await remoteDataSource.checkEmailVerification();
      if (result) {
        // Persist verified state to Hive so cold reboots load the correct flag.
        final cachedUser = await localDataSource.getCachedUser();
        if (cachedUser != null && !cachedUser.isEmailVerified) {
          await localDataSource.cacheUser(
            cachedUser.copyWith(isEmailVerified: true),
          );
        }
      }
      return (isEmailVerified: result, failure: null);
    } on Failure catch (failure) {
      return (isEmailVerified: false, failure: failure);
    } catch (e) {
      return (
        isEmailVerified: false,
        failure: const ServerFailure(message: 'Failed to check email verification'),
      );
    }
  }
}