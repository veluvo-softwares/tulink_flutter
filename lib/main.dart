import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:tulink_flutter/features/maps/presentation/tulink_map_screen.dart';

import 'core/config/app_config.dart';
import 'core/di/service_locator.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/tulink_colors.dart';
import 'core/navigation/app_router.dart';
import 'core/navigation/main_navigation_screen.dart';
import 'features/auth/data/models/user_model.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/auth/presentation/screens/auth_screen.dart';
import 'core/theme/theme_provider.dart';
import 'features/maps/presentation/providers/map_provider.dart';
import 'features/journeys/presentation/providers/journey_provider.dart';
import 'features/invites/presentation/providers/invite_provider.dart';

void main() {
  // Keep main() synchronous and minimal. The native splash stays up while
  // Dart loads. As soon as Flutter is ready we paint our own splash and run
  // heavy initialization in the background.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AppBootstrap());
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
        // Map Provider
        ChangeNotifierProvider<MapProvider>.value(
          value: serviceLocator.mapProvider,
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
          } else {
            return const MainNavigationScreen();
          }
        },
      ),
    );
  }

}
