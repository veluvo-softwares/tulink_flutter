import 'package:flutter/material.dart';

import 'package:tulink_flutter/main.dart';
import 'package:tulink_flutter/features/auth/presentation/screens/auth_screen.dart';
import 'package:tulink_flutter/features/home/presentation/screens/home_screen.dart';
import 'package:tulink_flutter/features/maps/presentation/tulink_map_screen.dart';
import 'main_navigation_screen.dart';
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

      case MainNavigationScreen.routeName:
        return _createRoute(
          const MainNavigationScreen(),
          settings,
        );

      case HomeScreen.routeName:
        return _createRoute(
          const HomeScreen(),
          settings,
        );

      case TulinkMapScreen.routeName:
        return _createRoute(
          const TulinkMapScreen(),
          settings,
        );

      case AuthScreen.routeName:
        return _createRoute(
          const AuthScreen(),
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

}

/// Route constants for type-safe navigation
/// Centralizes all route names in one place
abstract class Routes {
  /// Home page route (entry logic)
  static const String home = HomePage.routeName;
  
  /// Main navigation route (Dashboard)
  static const String main = MainNavigationScreen.routeName;

  /// Map screen route
  static const String map = TulinkMapScreen.routeName;
  
  /// Authentication screen route
  static const String auth = AuthScreen.routeName;
  
  /// Root route (alias for home)
  static const String root = '/';
}