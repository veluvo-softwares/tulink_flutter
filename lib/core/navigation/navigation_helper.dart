import 'package:flutter/material.dart';

import 'app_router.dart';

/// Helper utilities for navigation throughout the app
/// Provides type-safe navigation methods with argument support
class NavigationHelper {
  NavigationHelper._();

  /// Navigate to sign-up screen with optional initial email
  static Future<void> toSignUp(
    BuildContext context, {
    String? initialEmail,
  }) async {
    final args = initialEmail != null ? {'email': initialEmail} : null;
    
    await Navigator.pushNamed(
      context,
      Routes.signUp,
      arguments: args,
    );
  }

  /// Navigate to home screen
  static Future<void> toHome(BuildContext context) async {
    await Navigator.pushNamed(context, Routes.home);
  }

  /// Replace current route with home
  static Future<void> toHomeAndClearStack(BuildContext context) async {
    await Navigator.pushNamedAndRemoveUntil(
      context,
      Routes.home,
      (route) => false,
    );
  }

  /// Go back to previous screen
  static void goBack(BuildContext context) {
    Navigator.pop(context);
  }

  /// Check if we can go back
  static bool canGoBack(BuildContext context) {
    return Navigator.canPop(context);
  }

  /// Example of navigating with complex arguments
  static Future<void> toSignUpWithComplexArgs(
    BuildContext context, {
    required String email,
    String? referralCode,
    Map<String, dynamic>? metadata,
  }) async {
    final args = <String, dynamic>{
      'email': email,
      if (referralCode != null) 'referralCode': referralCode,
      if (metadata != null) 'metadata': metadata,
    };

    await Navigator.pushNamed(
      context,
      Routes.signUp,
      arguments: args,
    );
  }
}