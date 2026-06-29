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
import 'package:tulink_flutter/features/maps/presentation/tulink_map_screen.dart';

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
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp();

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    FlutterError.onError =
        FirebaseCrashlytics.instance.recordFlutterFatalError;

    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(!kDebugMode);

    runApp(const AppBootstrap());
  }, (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
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

      final sl = ServiceLocator();
      await sl.init();

      // Mapbox SDK registers a ConnectivityManager callback + CPU monitor
      // on first touch — defer it until after Flutter is up.
      MapboxOptions.setAccessToken(AppConfig.mapboxAccessToken);

      if (mounted) setState(() => _serviceLocator = sl);
    } catch (e) {
      if (mounted) setState(() => _bootError = e);
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
      home: _SplashScreen(error: _bootError),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  final Object? error;
  const _SplashScreen({this.error});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;

    return Scaffold(
      backgroundColor: colors.carbonBlack,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'TULINK',
              style: TextStyle(
                color: colors.electricRed,
                fontSize: 40,
                fontWeight: FontWeight.w900,
                letterSpacing: 6,
              ),
            ),
            const SizedBox(height: 24),
            if (error == null)
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(colors.electricRed),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Startup failed: $error',
                  style: TextStyle(color: colors.silver, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    required this.serviceLocator,
  });

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
        ChangeNotifierProvider.value(
          value: serviceLocator.analyticsProvider,
        ),
        // Convoy Provider
        ChangeNotifierProvider.value(
          value: serviceLocator.convoyProvider,
        ),
        // Push notification service (FCM) — plain Provider, not a notifier.
        Provider<PushNotificationService>.value(
          value: serviceLocator.pushNotificationService,
        ),
      ],
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

            // Initial route
            initialRoute: HomePage.routeName,
          );
        },
      ),
    );
  }
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
          if (authProvider.isLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
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
