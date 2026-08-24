import 'package:flutter/material.dart';

import 'package:tulink_flutter/main.dart';
import 'package:tulink_flutter/features/auth/presentation/screens/auth_screen.dart';
import 'package:tulink_flutter/features/auth/presentation/screens/sign_up_screen.dart';
import 'package:tulink_flutter/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:tulink_flutter/features/auth/presentation/screens/verify_email_screen.dart';
import 'package:tulink_flutter/features/home/presentation/screens/home_screen.dart';
import 'package:tulink_flutter/features/maps/presentation/map_route_redirect_screen.dart';
import 'package:tulink_flutter/features/journeys/presentation/pages/create_journey_screen.dart';
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
        return _createRoute(const HomePage(), settings);

      case MainNavigationScreen.routeName:
        return _createRoute(const MainNavigationScreen(), settings);

      case HomeScreen.routeName:
        return _createRoute(const HomeScreen(), settings);

      // Retired: the map is hosted by the Home shell, not navigated to.
      // Kept so stale deep links redirect instead of 404-ing.
      case MapRouteRedirectScreen.routeName:
        return _createRoute(
          MapRouteRedirectScreen(arguments: settings.arguments),
          settings,
        );

      case AuthScreen.routeName:
        return _createRoute(const AuthScreen(), settings);

      case SignUpScreen.routeName:
        return _createRoute(const SignUpScreen(), settings);

      case ForgotPasswordScreen.routeName:
        return _createRoute(const ForgotPasswordScreen(), settings);

      case VerifyEmailScreen.routeName:
        return _createRoute(const VerifyEmailScreen(), settings);

      case CreateJourneyScreen.routeName:
        return _createRoute(const CreateJourneyScreen(), settings);

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

      // Retired page. A journey that has not started is staging chrome over
      // the persistent map, not a screen you navigate to, so this name lands on
      // the same redirect as `/mapview`: it makes the named journey current and
      // returns to the shell, which stages it.
      case MapRouteRedirectScreen.legacyJourneyPreviewRouteName:
        return _createRoute(
          MapRouteRedirectScreen(arguments: settings.arguments),
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
        return _createRoute(const JourneyHistoryScreen(), settings);

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
        return _createRoute(JourneyDetailsScreen(journey: journey), settings);

      case ProfileScreen.routeName:
        return _createRoute(const ProfileScreen(), settings);

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

  /// Helper method to create MaterialPageRoute with consistent settings.
  ///
  /// The route is typed `Object?` rather than by the widget type: a
  /// `MaterialPageRoute<SomeScreen>` treats its *pop result* as a
  /// `SomeScreen`, so any screen popping a plain value (a String, a bool)
  /// throws `type 'X' is not a subtype of type 'Widget?' of 'result'`.
  static MaterialPageRoute<Object?> _createRoute<T extends Widget>(
    T widget,
    RouteSettings settings,
  ) {
    return MaterialPageRoute<Object?>(
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

  /// Retired map route. Redirects to the shell; see
  /// [MapRouteRedirectScreen].
  static const String map = MapRouteRedirectScreen.routeName;

  /// Authentication screen route
  static const String auth = AuthScreen.routeName;

  /// Email verification screen route
  static const String verifyEmail = VerifyEmailScreen.routeName;

  /// Root route (alias for home)
  static const String root = '/';
}
