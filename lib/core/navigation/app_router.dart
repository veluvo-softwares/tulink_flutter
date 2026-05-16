import 'package:flutter/material.dart';

import 'package:tulink_flutter/main.dart';
import 'package:tulink_flutter/features/auth/presentation/screens/auth_screen.dart';
import 'package:tulink_flutter/features/home/presentation/screens/home_screen.dart';
import 'package:tulink_flutter/features/maps/presentation/tulink_map_screen.dart';
import 'package:tulink_flutter/features/journeys/presentation/pages/create_journey_screen.dart';
import 'package:tulink_flutter/features/journeys/presentation/pages/journey_preview_screen.dart';
import 'package:tulink_flutter/features/journeys/presentation/pages/invite_participants_screen.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';
import 'package:tulink_flutter/features/analytics/presentation/screens/journey_history_screen.dart';
import 'package:tulink_flutter/features/analytics/presentation/screens/journey_details_screen.dart';
import 'package:tulink_flutter/features/profile/presentation/screens/profile_screen.dart';
import 'package:tulink_flutter/features/invites/presentation/pages/invitations_screen.dart';
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

      case CreateJourneyScreen.routeName:
        return _createRoute(
          const CreateJourneyScreen(),
          settings,
        );

      case CreateJourneyScreen.editRouteName:
        final journey = settings.arguments as Journey?;
        if (journey == null) {
          return _createRoute(
            UndefinedRouteScreen(
              undefinedRouteName: 'Edit Journey - Missing Journey Data',
            ),
            settings,
          );
        }
        return _createRoute(
          CreateJourneyScreen(journey: journey, isEdit: true),
          settings,
        );

      case JourneyPreviewScreen.routeName:
        final journeyId = settings.arguments as String?;
        if (journeyId == null) {
          return _createRoute(
            UndefinedRouteScreen(
              undefinedRouteName: 'Journey Preview - Missing ID',
            ),
            settings,
          );
        }
        return _createRoute(
          JourneyPreviewScreen(journeyId: journeyId),
          settings,
        );

      case InviteParticipantsScreen.routeName:
        final journeyId = settings.arguments as String?;
        if (journeyId == null) {
          return _createRoute(
            UndefinedRouteScreen(
              undefinedRouteName: 'Invite Participants - Missing ID',
            ),
            settings,
          );
        }
        return _createRoute(
          InviteParticipantsScreen(journeyId: journeyId),
          settings,
        );

      case InvitationsScreen.routeName:
        return _createRoute(const InvitationsScreen(), settings);

      case JourneyHistoryScreen.routeName:
        return _createRoute(
          const JourneyHistoryScreen(),
          settings,
        );

      case JourneyDetailsScreen.routeName:
        final journey = settings.arguments as Journey?;
        if (journey == null) {
          return _createRoute(
            UndefinedRouteScreen(
              undefinedRouteName: 'Journey Details - Missing Journey Data',
            ),
            settings,
          );
        }
        return _createRoute(
          JourneyDetailsScreen(journey: journey),
          settings,
        );

      case ProfileScreen.routeName:
        return _createRoute(
          const ProfileScreen(),
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