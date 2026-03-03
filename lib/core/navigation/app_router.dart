import 'package:flutter/material.dart';

import 'package:tulink_flutter/features/auth/presentation/screens/sign_up_screen.dart';
import 'package:tulink_flutter/main.dart';
import 'undefined_route_screen.dart';

/// Centralized router for handling all navigation throughout the app
/// Uses native Flutter Navigator APIs with type-safe argument handling
class AppRouter {
  AppRouter._();

  /// Generates routes based on RouteSettings
  /// Handles argument extraction and type-safe casting for destination widgets
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
      case HomePage.routeName:
        return _createRoute(
          const HomePage(),
          settings,
        );

      case SignUpScreen.routeName:
        // Example of argument handling - SignUpScreen could accept initial email
        final args = settings.arguments;
        String? initialEmail;
        
        if (args is Map<String, dynamic>) {
          initialEmail = _safeCast<String>(args['email']);
        } else if (args is String) {
          initialEmail = args;
        }
        
        return _createRoute(
          SignUpScreen(initialEmail: initialEmail),
          settings,
        );

      // 404 Error Handling - Default case for undefined routes
      default:
        return _createRoute(
          UndefinedRouteScreen(
            undefinedRouteName: settings.name ?? 'Unknown Route',
          ),
          settings,
        );
    }
  }

  /// Helper method to create MaterialPageRoute with consistent settings
  static MaterialPageRoute<T> _createRoute<T extends Widget>(
    T widget,
    RouteSettings settings,
  ) {
    return MaterialPageRoute<T>(
      builder: (context) => widget,
      settings: settings,
    );
  }

  /// Safe type casting utility for arguments
  /// Returns null if cast fails instead of throwing exception
  static T? _safeCast<T>(dynamic value) {
    try {
      return value as T?;
    } catch (e) {
      debugPrint('AppRouter: Failed to cast $value to $T: $e');
      return null;
    }
  }
}

/// Route constants for type-safe navigation
/// Centralizes all route names in one place
abstract class Routes {
  /// Home page route
  static const String home = HomePage.routeName;
  
  /// Sign up screen route
  static const String signUp = SignUpScreen.routeName;
  
  /// Root route (alias for home)
  static const String root = '/';
}