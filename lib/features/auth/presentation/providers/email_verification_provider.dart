import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:tulink_flutter/core/errors/failure.dart';
import 'package:tulink_flutter/core/services/car_toast_service.dart';
import 'package:tulink_flutter/features/auth/presentation/providers/auth_provider.dart';

/// State provider for the email verification screen.
///
/// Handles background polling (every 5 s) for email verification status,
/// the resend-verification-email action with a 60-second cooldown, and
/// the "already verified" info toast (SCR-06).
///
/// Navigation on successful verification is handled declaratively by the
/// screen Consumer — this provider only flips [isEmailVerified] to true.
class EmailVerificationProvider extends ChangeNotifier {
  /// Creates the provider, injecting the shared [AuthProvider] (D-03).
  EmailVerificationProvider(this._authProvider);

  final AuthProvider _authProvider;

  // ---------------------------------------------------------------------------
  // State fields
  // ---------------------------------------------------------------------------

  bool _isPolling = false;
  bool _isResending = false;
  int _resendCooldownSeconds = 0;
  bool _isEmailVerified = false;
  Timer? _pollTimer;
  Timer? _cooldownTimer;

  // ---------------------------------------------------------------------------
  // Public getters
  // ---------------------------------------------------------------------------

  /// Whether background polling is currently active.
  bool get isPolling => _isPolling;

  /// Whether a resend request is in flight.
  bool get isResending => _isResending;

  /// Seconds remaining until resend is allowed again (0 means ready).
  int get resendCooldownSeconds => _resendCooldownSeconds;

  /// True once the backend confirms that the user's email is verified.
  bool get isEmailVerified => _isEmailVerified;

  /// The user's email address, read live from the injected [AuthProvider].
  String? get userEmail => _authProvider.user?.email;

  /// Whether the user can trigger a resend right now.
  ///
  /// False when a cooldown is active or a resend is already in progress.
  bool get canResend => _resendCooldownSeconds == 0 && !_isResending;

  // ---------------------------------------------------------------------------
  // Polling
  // ---------------------------------------------------------------------------

  /// Start background polling every 5 seconds.
  ///
  /// Idempotent — calling this when already polling is a no-op (T-02-02).
  /// Does NOT call [notifyListeners]; polling is invisible to the UI.
  void startPolling() {
    if (_isPolling) return;
    _isPolling = true;
    _pollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkVerificationStatus(),
    );
  }

  /// Stop background polling and cancel the timer.
  ///
  /// Does NOT call [notifyListeners]; stopping is invisible to the UI.
  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _isPolling = false;
  }

  /// Internal: check the backend for email verification status.
  ///
  /// - On verified (result == true, was NOT already verified): call
  ///   [AuthProvider.markEmailVerified], stop polling, flip [isEmailVerified].
  /// - On already verified (result == true, WAS already verified — SCR-06):
  ///   show an info toast, stop polling, flip [isEmailVerified]. The toast is
  ///   only placed here, never inside [resendVerificationEmail].
  /// - On not-yet-verified (result == false): silently continue polling.
  Future<void> _checkVerificationStatus() async {
    // Snapshot the pre-call state so we can detect the SCR-06 "already
    // verified" path (the user was verified before this polling session).
    final alreadyVerified = _authProvider.isEmailVerified;

    final result = await _authProvider.checkEmailVerification();

    if (result) {
      if (alreadyVerified) {
        // SCR-06: user was already verified before this session started.
        CarToastService.showInfo('Your email is already verified');
      } else {
        // Normal path: user just clicked the link.
        _authProvider.markEmailVerified();
      }
      stopPolling();
      _isEmailVerified = true;
      notifyListeners();
    }
    // result == false: poll continues silently, no toast.
  }

  // ---------------------------------------------------------------------------
  // Resend
  // ---------------------------------------------------------------------------

  /// Trigger sending a new verification email.
  ///
  /// Guards:
  /// - Returns immediately if [canResend] is false (cooldown or in-flight).
  ///
  /// On success: starts the 60-second cooldown.
  /// On failure: shows an error toast based on the failure type (SCR-05).
  Future<void> resendVerificationEmail() async {
    if (!canResend) return;

    _setResending(true);

    final success = await _authProvider.sendEmailVerification();

    if (success) {
      _setResending(false);
      _startCooldown();
    } else {
      // Map the failure type to a user-friendly message (SCR-05).
      final failure = _authProvider.failure;
      if (failure is AuthFailure || failure?.statusCode == 401) {
        CarToastService.showError('Session expired, please sign in again');
      } else if (failure is ValidationFailure || failure?.statusCode == 400) {
        CarToastService.showError('Account has no email address');
      } else {
        CarToastService.showError("Couldn't resend — please try again");
      }
      _setResending(false);
    }
  }

  // ---------------------------------------------------------------------------
  // Cooldown
  // ---------------------------------------------------------------------------

  /// Start the 60-second resend cooldown (SCR-04).
  void _startCooldown() {
    _resendCooldownSeconds = 60;
    notifyListeners();

    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _resendCooldownSeconds--;
      if (_resendCooldownSeconds <= 0) {
        _resendCooldownSeconds = 0;
        _cooldownTimer?.cancel();
        _cooldownTimer = null;
      }
      notifyListeners();
    });
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _setResending(bool value) {
    _isResending = value;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    stopPolling();
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
    super.dispose();
  }
}
