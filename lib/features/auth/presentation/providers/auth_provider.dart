import 'package:flutter/foundation.dart';

import '../../../../core/auth/token_manager.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/services/car_toast_service.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';

/// Authentication state management using ChangeNotifier
class AuthProvider extends ChangeNotifier {
  AuthProvider(this._authRepository) {
    TokenManager().onAuthLost = _handleAuthLost;
  }

  final AuthRepository _authRepository;

  /// Hook invoked when the session ends (explicit sign-out OR an unrecoverable
  /// auth-lost). Wired in ServiceLocator to tear down live convoy coordination
  /// and the user WebSocket channel so a signed-out client stops publishing GPS.
  VoidCallback? onSessionEnded;

  // State variables
  UserEntity? _user;
  bool _isLoading = false;
  bool _isInitialized = false;
  Failure? _failure;
  bool _isSignedIn = false;

  // Getters
  UserEntity? get user => _user;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  Failure? get failure => _failure;
  bool get isSignedIn => _isSignedIn;
  String get errorMessage => _failure?.message ?? '';
  bool get hasError => _failure != null;

  /// Initialize auth state
  Future<void> initialize() async {
    _setLoading(true);

    try {
      _isSignedIn = await _authRepository.isSignedIn();

      if (_isSignedIn) {
        final result = await _authRepository.getCurrentUser();
        if (result.failure == null) {
          _user = result.user;
        } else {
          _isSignedIn = false;
          _setFailure(result.failure);
        }
      }
    } catch (e) {
      _isSignedIn = false;
      _setFailure(const ServerFailure(message: 'Initialization failed'));
    } finally {
      _isInitialized = true;
      _setLoading(false);
    }
  }

  /// Sign in with email and password
  Future<bool> signIn({required String email, required String password}) async {
    print('🔵 AuthProvider.signIn() called with email: $email');
    _setLoading(true);
    _clearFailure();

    try {
      print('📞 AuthProvider calling _authRepository.signIn()...');
      final result = await _authRepository.signIn(
        email: email,
        password: password,
      );
      print(
        '✅ AuthProvider received result: user=${result.user?.email}, failure=${result.failure}',
      );

      if (result.failure == null) {
        _user = result.user;
        _isSignedIn = true;
        _setLoading(false);

        if (result.user?.isEmailVerified == true) {
          CarToastService.showSuccess(
            'Welcome back, ${result.user?.name ?? 'User'}!',
          );
        }

        return true;
      } else {
        _setFailure(result.failure);
        _setLoading(false);

        // Show error toast with specific message
        CarToastService.showError(_getErrorMessage(result.failure));

        return false;
      }
    } catch (e) {
      _setFailure(const ServerFailure(message: 'Sign in failed'));
      _setLoading(false);
      return false;
    }
  }

  /// Sign up with email, password and name
  Future<bool> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    _setLoading(true);
    _clearFailure();

    try {
      final result = await _authRepository.signUp(
        email: email,
        password: password,
        name: name,
      );

      if (result.failure == null) {
        _user = result.user;
        _isSignedIn = true;
        _setLoading(false);

        if (result.user?.isEmailVerified == true) {
          CarToastService.showSuccess(
            'Account created successfully! Welcome ${result.user?.name ?? 'User'}!',
          );
        }

        return true;
      } else {
        _setFailure(result.failure);
        _setLoading(false);

        // Show error toast with specific message
        CarToastService.showError(_getErrorMessage(result.failure));

        return false;
      }
    } catch (e) {
      _setFailure(const ServerFailure(message: 'Sign up failed'));
      _setLoading(false);
      return false;
    }
  }

  /// Sign out current user
  Future<bool> signOut() async {
    _setLoading(true);
    _clearFailure();

    try {
      final result = await _authRepository.signOut();

      if (result.success) {
        // Stop convoy GPS publishing + WebSocket BEFORE clearing user state so a
        // signed-out client never keeps emitting location updates (D11-1).
        onSessionEnded?.call();
        _user = null;
        _isSignedIn = false;
        _setLoading(false);
        return true;
      } else {
        _setFailure(result.failure);
        _setLoading(false);

        // Show error toast
        CarToastService.showError('Failed to sign out. Please try again.');

        return false;
      }
    } catch (e) {
      _setFailure(const ServerFailure(message: 'Sign out failed'));
      _setLoading(false);
      return false;
    }
  }

  /// Called by TokenManager when an unrecoverable auth failure clears the
  /// stored tokens (refresh expired, token revoked). Resets local user state
  /// so the UI flips to AuthScreen on the next rebuild.
  void _handleAuthLost() {
    if (!_isSignedIn && _user == null) return;
    // Tear down convoy coordination + user channel on unrecoverable auth loss too.
    onSessionEnded?.call();
    _user = null;
    _isSignedIn = false;
    notifyListeners();
  }

  /// Refresh authentication token
  Future<bool> refreshToken() async {
    try {
      final result = await _authRepository.refreshToken();

      if (result.failure != null) {
        _setFailure(result.failure);
        return false;
      }
      return true;
    } catch (e) {
      _setFailure(const ServerFailure(message: 'Token refresh failed'));
      return false;
    }
  }

  /// Update user profile
  Future<bool> updateProfile({String? name, String? profilePicture}) async {
    _setLoading(true);
    _clearFailure();

    try {
      final result = await _authRepository.updateProfile(
        name: name,
        profilePicture: profilePicture,
      );

      if (result.failure == null) {
        _user = result.user;
        _setLoading(false);
        return true;
      } else {
        _setFailure(result.failure);
        _setLoading(false);
        return false;
      }
    } catch (e) {
      _setFailure(const ServerFailure(message: 'Profile update failed'));
      _setLoading(false);
      return false;
    }
  }

  /// Reset password
  Future<bool> resetPassword({required String email}) async {
    _setLoading(true);
    _clearFailure();

    try {
      final result = await _authRepository.resetPassword(email: email);

      if (result.success) {
        _setLoading(false);

        // Show success toast
        CarToastService.showSuccess('Password reset email sent successfully!');

        return true;
      } else {
        _setFailure(result.failure);
        _setLoading(false);

        // Show error toast
        CarToastService.showError(_getErrorMessage(result.failure));

        return false;
      }
    } catch (e) {
      _setFailure(const ServerFailure(message: 'Password reset failed'));
      _setLoading(false);
      return false;
    }
  }

  /// Verify email
  Future<bool> verifyEmail({required String token}) async {
    _setLoading(true);
    _clearFailure();

    try {
      final result = await _authRepository.verifyEmail(token: token);

      if (result.success && _user != null) {
        _user = _user!.copyWith(isEmailVerified: true);
        _setLoading(false);
        return true;
      } else {
        _setFailure(result.failure);
        _setLoading(false);
        return false;
      }
    } catch (e) {
      _setFailure(const ServerFailure(message: 'Email verification failed'));
      _setLoading(false);
      return false;
    }
  }

  /// Delete user account
  Future<bool> deleteAccount() async {
    _setLoading(true);
    _clearFailure();

    try {
      final result = await _authRepository.deleteAccount();

      if (result.success) {
        onSessionEnded?.call();
        _user = null;
        _isSignedIn = false;
        _setLoading(false);
        return true;
      } else {
        _setFailure(result.failure);
        _setLoading(false);
        return false;
      }
    } catch (e) {
      _setFailure(const ServerFailure(message: 'Account deletion failed'));
      _setLoading(false);
      return false;
    }
  }

  /// Whether the currently cached user has a verified email address.
  bool get isEmailVerified => _user?.isEmailVerified ?? false;

  /// Sign in / sign up with Google.
  Future<bool> signInWithGoogle() =>
      _signInWithSocial(_authRepository.signInWithGoogle);

  /// Sign in / sign up with Apple.
  Future<bool> signInWithApple() =>
      _signInWithSocial(_authRepository.signInWithApple);

  /// Shared driver for the social flows — mirrors signIn()'s state handling,
  /// but silently ignores a user-cancelled native flow (no error toast).
  Future<bool> _signInWithSocial(
    Future<({UserEntity? user, String? token, Failure? failure})> Function()
    run,
  ) async {
    _setLoading(true);
    _clearFailure();

    try {
      final result = await run();

      if (result.failure == null) {
        _user = result.user;
        _isSignedIn = true;
        _setLoading(false);

        if (result.user?.isEmailVerified == true) {
          CarToastService.showSuccess(
            'Welcome, ${result.user?.name ?? 'User'}!',
          );
        }
        return true;
      }

      // User backed out of the native sheet — clear loading and stay quiet.
      final failure = result.failure!;
      if (failure is AuthFailure && failure.isCancellation) {
        _clearFailure();
        _setLoading(false);
        return false;
      }

      _setFailure(failure);
      _setLoading(false);
      CarToastService.showError(_getErrorMessage(failure));
      return false;
    } catch (e) {
      _setFailure(const ServerFailure(message: 'Social sign-in failed'));
      _setLoading(false);
      return false;
    }
  }

  /// Update the local user cache to reflect a verified email.
  /// Called by EmailVerificationProvider when the poll confirms verification.
  void markEmailVerified() {
    if (_user == null) return;
    _user = _user!.copyWith(isEmailVerified: true);
    notifyListeners();
  }

  /// Trigger sending the verification email for the authenticated user.
  /// Follows the resetPassword() pattern with _setLoading guards.
  /// No toast from this method — EmailVerificationProvider handles toast messaging.
  Future<bool> sendEmailVerification() async {
    _setLoading(true);
    _clearFailure();

    try {
      final result = await _authRepository.sendEmailVerification();

      if (result.success) {
        _setLoading(false);
        return true;
      } else {
        _setFailure(result.failure);
        _setLoading(false);
        return false;
      }
    } catch (e) {
      _setFailure(
        const ServerFailure(message: 'Failed to send verification email'),
      );
      _setLoading(false);
      return false;
    }
  }

  /// Check whether the currently signed-in user's email is verified.
  /// Does NOT set isLoading — the 5-second background poll must not flicker UI.
  /// Transient network errors return false and are silently retried by the polling timer.
  Future<bool> checkEmailVerification() async {
    try {
      final result = await _authRepository.checkEmailVerification();
      return result.isEmailVerified;
    } catch (e) {
      return false;
    }
  }

  // Helper methods
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setFailure(Failure? failure) {
    _failure = failure;
    notifyListeners();
  }

  void _clearFailure() {
    _failure = null;
    notifyListeners();
  }

  /// Clear all error messages
  void clearError() {
    _clearFailure();
  }

  /// Get user-friendly error message from failure
  String _getErrorMessage(Failure? failure) {
    if (failure == null) return 'An unexpected error occurred';

    switch (failure.runtimeType) {
      case AuthFailure:
        return 'Invalid email or password. Please check your credentials.';
      case NetworkFailure:
        return 'Network connection issue. Please check your internet connection.';
      case ServerFailure:
        return failure.message.isNotEmpty
            ? failure.message
            : 'Server error. Please try again later.';
      case ValidationFailure:
        return failure.message.isNotEmpty
            ? failure.message
            : 'Please check your input and try again.';
      case TokenFailure:
        return 'Session expired. Please sign in again.';
      default:
        return failure.message.isNotEmpty
            ? failure.message
            : 'Something went wrong. Please try again.';
    }
  }
}
