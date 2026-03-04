import 'package:flutter/material.dart';

import 'app_router.dart';

/// Helper utilities for navigation throughout the app
/// Provides type-safe navigation methods with argument support
class NavigationHelper {
  NavigationHelper._();

  /// Navigate to authentication screen
  static Future<void> toAuth(BuildContext context) async {
    await Navigator.pushNamed(context, Routes.auth);
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

  /// Navigate to authentication screen and replace current route
  static Future<void> toAuthAndClearStack(BuildContext context) async {
    await Navigator.pushNamedAndRemoveUntil(
      context,
      Routes.auth,
      (route) => false,
    );
  }
}