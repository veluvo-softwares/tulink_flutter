import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:provider/provider.dart';

import 'core/config/app_config.dart';
import 'core/di/service_locator.dart';
import 'core/services/push_notification_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/tulink_colors.dart';
import 'core/navigation/app_router.dart';
import 'core/navigation/main_navigation_screen.dart';
import 'features/auth/data/models/user_model.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/auth/presentation/providers/email_verification_provider.dart';
import 'features/auth/presentation/screens/auth_screen.dart';
import 'features/auth/presentation/screens/verify_email_screen.dart';
import 'features/convoy/presentation/services/live_journey_coordinator.dart';
import 'core/theme/theme_provider.dart';
import 'features/maps/presentation/providers/map_provider.dart';
import 'features/maps/presentation/providers/navigation_provider.dart';
import 'features/journeys/presentation/providers/journey_provider.dart';
import 'features/invites/presentation/providers/invite_provider.dart';

/// Handles FCM messages that arrive while the app is in the background or
/// terminated. Must be a top-level function. The OS renders the notification;
/// this runs in a separate isolate, so keep it lightweight.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('📦 FCM background message: ${message.messageId}');
}

void main() {
  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      // Keep the native branded launch screen visible until Flutter has
      // finished bootstrapping. This avoids showing a second, mismatched
      // in-app splash while Firebase, Hive, Mapbox, and services initialize.
      WidgetsBinding.instance.deferFirstFrame();
      await Firebase.initializeApp();

      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );

      FlutterError.onError =
          FirebaseCrashlytics.instance.recordFlutterFatalError;

      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };

      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
        !kDebugMode,
      );

      runApp(const AppBootstrap());
    },
    (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    },
  );
}

/// Boots the app: shows a splash, runs heavy init in the background, then
/// swaps to [MyApp] once dependencies are ready.
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  ServiceLocator? _serviceLocator;
  Object? _bootError;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      // .env is small and synchronous-ish; needed before AppConfig is touched.
      await dotenv.load(fileName: '.env');

      // Hive must be ready before the first box is opened by ServiceLocator.
      await Hive.initFlutter();
      Hive.registerAdapter(UserModelAdapter());

      // OfflineManager/TileStore are initialized by ServiceLocator and need
      // the token before their first native SDK call.
      MapboxOptions.setAccessToken(AppConfig.mapboxAccessToken);

      final sl = ServiceLocator();
      await sl.init();

      if (mounted) setState(() => _serviceLocator = sl);
    } catch (e) {
      if (mounted) setState(() => _bootError = e);
    } finally {
      // A startup failure still needs to release the native launch screen so
      // the fallback can report the problem instead of leaving the app frozen.
      WidgetsBinding.instance.allowFirstFrame();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sl = _serviceLocator;
    if (sl != null) {
      return MyApp(serviceLocator: sl);
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.tulinkTheme,
      darkTheme: AppTheme.tulinkTheme,
      themeMode: ThemeMode.dark,
      home: _StartupFallback(error: _bootError),
    );
  }
}

class _StartupFallback extends StatelessWidget {
  final Object? error;
  const _StartupFallback({this.error});

  @override
  Widget build(BuildContext context) {
    if (error == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: Theme.of(context).tulinkColors.warmSand,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text('Startup failed: $error', textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.serviceLocator});

  final ServiceLocator serviceLocator;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Theme Provider
        ChangeNotifierProvider<ThemeProvider>.value(
          value: serviceLocator.themeProvider,
        ),
        // Auth Provider
        ChangeNotifierProvider<AuthProvider>.value(
          value: serviceLocator.authProvider,
        ),
        // Email Verification Provider
        ChangeNotifierProvider<EmailVerificationProvider>.value(
          value: serviceLocator.emailVerificationProvider,
        ),
        // Map Provider
        ChangeNotifierProvider<MapProvider>.value(
          value: serviceLocator.mapProvider,
        ),
        // Navigation Provider
        ChangeNotifierProvider<NavigationProvider>.value(
          value: serviceLocator.navigationProvider,
        ),
        // Journey Provider
        ChangeNotifierProvider<JourneyProvider>.value(
          value: serviceLocator.journeyProvider,
        ),
        // Invite Provider
        ChangeNotifierProvider<InviteProvider>.value(
          value: serviceLocator.inviteProvider,
        ),
        // Analytics Provider
        ChangeNotifierProvider.value(value: serviceLocator.analyticsProvider),
        // Convoy Provider
        ChangeNotifierProvider.value(value: serviceLocator.convoyProvider),
        Provider<LiveJourneyCoordinator>.value(
          value: serviceLocator.liveJourneyCoordinator,
        ),
        // Push notification service (FCM) — plain Provider, not a notifier.
        Provider<PushNotificationService>.value(
          value: serviceLocator.pushNotificationService,
        ),
        Provider.value(value: serviceLocator.offlineMapService),
      ],
      child: _AppLifecycleCoordinator(
        onResumed: serviceLocator.liveJourneyCoordinator.onAppResumed,
        child: Consumer<ThemeProvider>(
          builder: (context, themeProvider, child) {
            return MaterialApp(
              title: 'TuLink Flutter',
              debugShowCheckedModeBanner: false,

              // Theme configuration - Tu-Link dark theme only
              theme: AppTheme.tulinkTheme,
              darkTheme: AppTheme.tulinkTheme,
              themeMode: ThemeMode.dark, // Tu-Link is dark mode only
              // Centralized routing with onGenerateRoute
              onGenerateRoute: AppRouter.generateRoute,

              // Start at the Navigator root. Using `/home` here makes Flutter's
              // initial-route expansion push both `/` and `/home`; because both
              // routes render HomePage, two HomeScreen trees were mounted and
              // every startup fetch/socket subscription ran twice.
              initialRoute: '/',
            );
          },
        ),
      ),
    );
  }
}

/// One app-scoped owner for transport recovery. Individual screens may still
/// restore their own visual resources, but they no longer race to reconnect
/// and rejoin the same journey room.
class _AppLifecycleCoordinator extends StatefulWidget {
  const _AppLifecycleCoordinator({
    required this.onResumed,
    required this.child,
  });

  final Future<void> Function() onResumed;
  final Widget child;

  @override
  State<_AppLifecycleCoordinator> createState() =>
      _AppLifecycleCoordinatorState();
}

class _AppLifecycleCoordinatorState extends State<_AppLifecycleCoordinator>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.onResumed());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class HomePage extends StatelessWidget {
  /// Route name for navigation
  static const String routeName = '/home';

  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          // Keep the authenticated subtree mounted during background auth
          // actions such as resending a verification email. Replacing the
          // verification screen with this spinner disposed and recreated it,
          // resetting its local state and producing a blank/remount loop when
          // the resend endpoint was rate-limited.
          if (!authProvider.isInitialized) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!authProvider.isSignedIn) {
            return const AuthScreen();
          } else if (!authProvider.isEmailVerified) {
            return const VerifyEmailScreen();
          } else {
            return const MainNavigationScreen();
          }
        },
      ),
    );
  }
}
